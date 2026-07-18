import { createServer } from "node:http";
import { existsSync, mkdirSync, writeFileSync, readFileSync, readdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve, extname } from "node:path";
import { homedir } from "node:os";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { Vault, VaultConflictError } from "./vault.mjs";
import { assignIds, itemView, findById, reflowUrgent, findDuplicate } from "./model.mjs";
import { unfurlUrl } from "./unfurl.mjs";
import { runAgent } from "./agent.mjs";
import { touch, ageDays } from "./ledger.mjs";
import { applyAction } from "./ops.mjs";
import { createMemory } from "./memory.mjs";
import { createNotes } from "./notes.mjs";
import { createCleanup } from "./cleanup.mjs";
import { createActivity } from "./activity.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const APP_VERSION = (() => {
  try { return JSON.parse(readFileSync(join(here, "..", "package.json"), "utf8")).version || "0.0.0"; }
  catch { return "0.0.0"; }
})();
const DEFAULT_PORT = Number(process.env.PORT) || 5178;
const DEFAULT_HOST = "127.0.0.1";

const BLANK_FILE = `# Todo List

## 🎯 Goals

### 🔴 Top 5 of the week

## 📚 To Read

### 🔴 Urgent

### 🔵 Normal

### ✅ Completed

### 🗑️ Deleted
`;

const DEMO_FILE = `# Todo List

## 🎯 Goals

**Launch** #launch
- Ship the next version

### 🔴 Top 5 of the week

- [ ] Finalize the launch plan #launch

## 📚 To Read

- https://docs.anthropic.com

### 🔴 Urgent

- [ ] ⭐ Review launch blockers #launch
- [ ] Prepare the stakeholder update #launch

### 🔵 Normal

- [ ] Draft the release notes #launch

### ✅ Completed

### 🗑️ Deleted
`;

const expandPath = (p) => resolve(String(p || "").replace(/^~(?=\/|$)/, homedir()));

const UPLOAD_LIMIT = 40_000_000; // ~30 MB after base64 inflation
const MIME = {
  ".pdf": "application/pdf", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
  ".gif": "image/gif", ".webp": "image/webp", ".svg": "image/svg+xml", ".txt": "text/plain; charset=utf-8",
  ".md": "text/markdown; charset=utf-8", ".markdown": "text/markdown; charset=utf-8", ".csv": "text/csv; charset=utf-8",
  ".json": "application/json", ".html": "text/html; charset=utf-8", ".zip": "application/zip",
  ".doc": "application/msword", ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ".xls": "application/vnd.ms-excel", ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  ".ppt": "application/vnd.ms-powerpoint", ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
};

// Remember the last-opened file so a restart reconnects instead of dropping to onboarding.
const STATE_DIR = process.env.BIGROCKS_STATE_DIR || join(homedir(), ".config", "big-rocks-first");
const LAST_FILE = join(STATE_DIR, "last-file");
function rememberFile(p) { try { mkdirSync(STATE_DIR, { recursive: true }); writeFileSync(LAST_FILE, p, "utf8"); } catch {} }
function recallFile() { try { const p = readFileSync(LAST_FILE, "utf8").trim(); return p && existsSync(p) ? p : null; } catch { return null; } }

// Per-file chat transcript + session (so a reload/restart keeps the conversation).
const CHATS_DIR = join(STATE_DIR, "chats");
const chatFile = (docPath) => join(CHATS_DIR, createHash("sha256").update(docPath).digest("hex").slice(0, 16) + ".json");
function loadChat(docPath) { try { return JSON.parse(readFileSync(chatFile(docPath), "utf8")); } catch { return { sessionId: undefined, messages: [] }; } }
function saveChat(docPath, data) { try { mkdirSync(CHATS_DIR, { recursive: true }); writeFileSync(chatFile(docPath), JSON.stringify(data), "utf8"); } catch {} }
const clone = (value) => structuredClone(value);
const conflictBody = (message) => ({ error: message, code: "VAULT_CONFLICT", conflict: true });

// --- Draft as a set of individually-reviewable changes -----------------------
const BUCKET_LABEL = { urgent: "Urgent", normal: "Normal", top5: "Top 5", parked: "Parked", completed: "Completed", deleted: "Deleted" };
const CHANGE_BUCKETS = ["urgent", "normal", "top5", "parked", "completed", "deleted"];
function indexItems(model) {
  const map = new Map();
  for (const b of CHANGE_BUCKETS) for (const it of model[b] ?? []) map.set(it.id, { item: it, bucket: b });
  return map;
}
// A structured, per-item diff of the draft against base — one reversible change each.
function diffModels(base, draft) {
  const changes = [];
  const B = indexItems(base), D = indexItems(draft);
  for (const [id, d] of D) {
    const b = B.get(id);
    if (!b) { changes.push({ key: `item:${id}`, kind: "added", label: `Added “${d.item.title}” to ${BUCKET_LABEL[d.bucket]}` }); continue; }
    if (b.bucket !== d.bucket) {
      if (d.bucket === "completed") changes.push({ key: `item:${id}`, kind: "completed", label: `Completed “${d.item.title}”` });
      else if (d.bucket === "deleted") changes.push({ key: `item:${id}`, kind: "deleted", label: `Deleted “${d.item.title}”` });
      else if (d.bucket === "parked") changes.push({ key: `item:${id}`, kind: "parked", label: `Parked “${d.item.title}”` });
      else changes.push({ key: `item:${id}`, kind: "moved", label: `Moved “${d.item.title}” → ${BUCKET_LABEL[d.bucket]}` });
    } else if (b.item.title !== d.item.title) {
      changes.push({ key: `item:${id}`, kind: "retitled", label: `“${b.item.title}” → “${d.item.title}”` });
    } else if (!!b.item.starred !== !!d.item.starred) {
      changes.push(d.item.starred
        ? { key: `item:${id}`, kind: "today", label: `Marked “${d.item.title}” Today` }
        : { key: `item:${id}`, kind: "untoday", label: `Cleared Today on “${d.item.title}”` });
    }
  }
  for (const [id, b] of B) if (!D.has(id)) changes.push({ key: `item:${id}`, kind: "removed", label: `Removed “${b.item.title}”` });
  if (JSON.stringify(base.goals?.rawLines ?? []) !== JSON.stringify(draft.goals?.rawLines ?? []))
    changes.push({ key: "goals", kind: "goals", label: "Edited the Goals notepad" });
  if (JSON.stringify(base.toread?.rawLines ?? []) !== JSON.stringify(draft.toread?.rawLines ?? []))
    changes.push({ key: "toread", kind: "toread", label: "Edited To Read" });
  return changes;
}
// Reject one change: mutate the draft so it no longer differs from base for that key.
function rejectChangeOn(base, draft, key) {
  if (key === "goals") { draft.goals = base.goals ? clone(base.goals) : undefined; return; }
  if (key === "toread") { draft.toread = base.toread ? clone(base.toread) : undefined; return; }
  if (!key.startsWith("item:")) return;
  const id = key.slice(5);
  const bInfo = findById(base, id), dInfo = findById(draft, id);
  if (bInfo && dInfo) {
    dInfo.item.title = bInfo.item.title;
    dInfo.item.starred = bInfo.item.starred;
    dInfo.item.checked = bInfo.item.checked;
    if (dInfo.bucket !== bInfo.bucket) { dInfo.arr.splice(dInfo.idx, 1); draft[bInfo.bucket].push(dInfo.item); }
  } else if (bInfo && !dInfo) {
    draft[bInfo.bucket].push(clone(bInfo.item));
  } else if (!bInfo && dInfo) {
    dInfo.arr.splice(dInfo.idx, 1);
  }
  reflowUrgent(draft);
}
// Approve one change: return a clone of base with just that change incorporated.
function applyChangeToBase(base, draft, key) {
  const next = clone(base);
  if (key === "goals") { next.goals = draft.goals ? clone(draft.goals) : draft.goals; return next; }
  if (key === "toread") { next.toread = draft.toread ? clone(draft.toread) : draft.toread; return next; }
  if (!key.startsWith("item:")) return next;
  const id = key.slice(5);
  const dInfo = findById(draft, id), nInfo = findById(next, id);
  if (dInfo && nInfo) {
    nInfo.item.title = dInfo.item.title;
    nInfo.item.starred = dInfo.item.starred;
    nInfo.item.checked = dInfo.item.checked;
    if (nInfo.bucket !== dInfo.bucket) { nInfo.arr.splice(nInfo.idx, 1); next[dInfo.bucket].push(nInfo.item); }
  } else if (dInfo && !nInfo) {
    next[dInfo.bucket].push(clone(dInfo.item));
  } else if (!dInfo && nInfo) {
    nInfo.arr.splice(nInfo.idx, 1);
  }
  reflowUrgent(next);
  return next;
}
// Small change sets are applied directly; larger ones are held for review.
const SMALL_CHANGE_LIMIT = 3;
function goalsLinesChanged(base, draft) {
  const a = base.goals?.rawLines ?? [], b = draft.goals?.rawLines ?? [];
  const setA = new Set(a), setB = new Set(b);
  let n = 0;
  for (const l of a) if (l.trim() && !setB.has(l)) n++;
  for (const l of b) if (l.trim() && !setA.has(l)) n++;
  return n;
}
function isSmallChangeSet(base, draft, changes) {
  if (changes.length > SMALL_CHANGE_LIMIT) return false;
  if (changes.some((c) => c.kind === "goals") && goalsLinesChanged(base, draft) > 6) return false;
  return true;
}
function flashInfo(changes) {
  return {
    items: changes.filter((c) => c.key.startsWith("item:")).map((c) => c.key.slice(5)),
    goals: changes.some((c) => c.kind === "goals"),
    toread: changes.some((c) => c.kind === "toread"),
  };
}
const execFileAsync = promisify(execFile);

export async function pickFileMac(mode) {
  if (process.platform !== "darwin") {
    const error = new Error("Native file navigation is currently available on macOS. Enter a path manually instead.");
    error.code = "PICKER_UNAVAILABLE";
    throw error;
  }
  const script = mode === "open"
    ? 'POSIX path of (choose file with prompt "Choose your Big Rocks Markdown file")'
    : 'POSIX path of (choose file name with prompt "Choose where to save your Big Rocks Markdown file" default name "todos.md")';
  try {
    const { stdout } = await execFileAsync("/usr/bin/osascript", ["-e", script]);
    return stdout.trim();
  } catch (cause) {
    if (String(cause?.stderr || cause?.message).includes("-128")) {
      const error = new Error("File selection cancelled.");
      error.code = "PICKER_CANCELLED";
      throw error;
    }
    throw cause;
  }
}

export function createBigRocksServer({
  initialTodoDocPath = process.env.TODO_FILE,
  agentRunner = runAgent,
  filePicker = pickFileMac,
} = {}) {
  let vault = null;
  let base = null;
  let baseVersion = null;
  let seen = {};
  let draft = null;
  let draftOps = [];
  let draftBaseVersion = null;
  let draftNoteEdits = []; // staged, reviewable edits to vault notes (never auto-applied)
  let externalConflict = false;
  const clearDraft = () => { draft = null; draftOps = []; draftBaseVersion = null; draftNoteEdits = []; };
  // Execute the currently-staged note edits. Appends/creates go through notes.mjs
  // (snapshotted there); moves/trashes go through the cleanup engine inside one
  // recoverable batch (manifest + before-copies). Runs in a deterministic order
  // (moves before trashes) and, crucially, a move/trash whose precondition fails
  // (the file changed on disk since it was staged) is SKIPPED, not forced — it's
  // returned in `keep` so the row stays in the panel for the user to re-ask.
  const CLEANUP_OPS = new Set(["move", "trash"]);
  const EXEC_ORDER = { move: 0, trash: 1, append: 2, create: 3 };
  function executeIntents(edits) {
    const m = createNotes(vault);
    const cleanup = createCleanup(vault);
    const batch = edits.some((e) => CLEANUP_OPS.has(e.op)) ? cleanup.openBatch() : null;
    const sorted = edits
      .map((e, i) => ({ e, i }))
      .sort((a, b) => (EXEC_ORDER[a.e.op] ?? 9) - (EXEC_ORDER[b.e.op] ?? 9) || a.i - b.i);
    const results = [], keep = [];
    for (const { e } of sorted) {
      try {
        if (CLEANUP_OPS.has(e.op)) {
          const r = cleanup.execute(e, batch);
          results.push({ label: e.label, ...r });
          if (r.skipped) keep.push(e);
        } else {
          results.push({ label: e.label, ...(e.op === "create" ? m.createNote(e.name, e.content) : m.appendToNote(e.name, e.content)) });
        }
      } catch (err) {
        // One op's filesystem error must never abort the batch — record it as
        // skipped (kept in the panel) so the rest apply and the manifest still
        // closes over whatever succeeded (so those ops stay undoable).
        results.push({ label: e.label, skipped: true, error: String(err?.message || err) });
        keep.push(e);
      }
    }
    if (batch) cleanup.closeBatch(batch);
    return { results, keep };
  }
  let sessionId;
  let chatMessages = [];
  let busy = false;
  let activeAbort = null;
  let lastActivity = null; // the most recent batch of activity-log appends (for the toast Undo)

  // Titles that just moved into Completed in this commit (by id — completing
  // preserves the item's id). Only linked ones are worth logging.
  function newlyCompleted(before, after) {
    const had = new Set((before?.completed || []).map((it) => it.id));
    return (after?.completed || []).filter((it) => !had.has(it.id)).map((it) => it.title).filter((t) => t.includes("[["));
  }
  // Deterministic, code-driven activity logging for the completions in a commit.
  // Returns { logged:[note names], suggest:[{note,line}] } for the client toast,
  // or null. Auto-appends only to notes that already have a `## Log` section.
  function applyActivityLog(before, after) {
    const titles = newlyCompleted(before, after);
    if (!titles.length) return null;
    const act = createActivity(vault);
    const logged = [], suggest = [], undo = [];
    for (const title of titles) {
      const r = act.logCompletion(title);
      for (const l of r.logged) logged.push(l.note);
      for (const s of r.suggest) suggest.push(s);
      undo.push(...r.undo);
    }
    if (undo.length) lastActivity = { undo };
    return logged.length || suggest.length ? { logged, suggest } : null;
  }

  function configured() {
    return !!vault;
  }

  function setVault(todoDocPath) {
    vault = new Vault({ todoDocPath: expandPath(todoDocPath) });
    reloadBase();
    clearDraft();
    externalConflict = false;
    const savedChat = loadChat(vault.todoDocPath);
    sessionId = savedChat.sessionId;
    chatMessages = savedChat.messages || [];
    rememberFile(vault.todoDocPath);
  }

  function configurePath(path, mode) {
    if (!path?.trim()) throw new Error("Choose a Markdown file path.");
    const doc = expandPath(path);
    if (mode === "open" && !existsSync(doc)) {
      const error = new Error("That file does not exist.");
      error.code = "FILE_NOT_FOUND";
      throw error;
    }
    if (mode === "blank" || mode === "demo") {
      if (existsSync(doc)) {
        const error = new Error("That file already exists. Choose a different name.");
        error.code = "FILE_EXISTS";
        throw error;
      }
      mkdirSync(dirname(doc), { recursive: true });
      writeFileSync(doc, mode === "demo" ? DEMO_FILE : BLANK_FILE, "utf8");
    }
    setVault(doc);
  }

  function reloadBase() {
    const loaded = vault.loadVersioned();
    base = assignIds(loaded.model);
    baseVersion = loaded.version;
    seen = touch(vault, base);
  }

  function refreshFromDisk() {
    if (!configured()) return;
    const current = vault.version();
    if (current === baseVersion) return;
    if (draft) {
      externalConflict = true;
    } else {
      reloadBase();
      sessionId = undefined;
    }
  }

  function currentModel() {
    return draft ?? base;
  }

  function modelView() {
    if (!configured()) return { configured: false, busy, appVersion: APP_VERSION };
    refreshFromDisk();
    const model = currentModel();
    const ageOf = (text) => { const a = ageDays(seen, text); return a != null && a >= 7 ? a : null; };
    const view = (it) => ({ ...itemView(it), age: ageOf(it.title) });
    const readLines = (section, prefix) => (section?.rawLines ?? [])
      .map((line, index) => ({ line, index, text: line.replace(prefix, "").trim() }))
      .filter((entry) => entry.text);
    const tags = [...new Set(["urgent", "normal", "top5"].flatMap((bucket) =>
      model[bucket].flatMap((it) => itemView(it).tags),
    ))].sort((a, b) => a.localeCompare(b));
    const baseGoals = base.goals?.rawLines ?? [];
    const draftGoals = model.goals?.rawLines ?? [];
    const goalsChanged = !!draft && JSON.stringify(baseGoals) !== JSON.stringify(draftGoals);
    return {
      configured: true,
      appVersion: APP_VERSION,
      todoDocPath: vault.todoDocPath,
      vaultDir: dirname(vault.todoDocPath),
      version: baseVersion,
      dirty: !!draft || draftNoteEdits.length > 0,
      ops: draftOps,
      changes: [
        ...(draft ? diffModels(base, draft) : []),
        ...draftNoteEdits.map((e, i) => ({ key: `note:${i}`, kind: e.kind || "note", label: e.label })),
      ],
      conflict: externalConflict,
      busy,
      canUndo: vault.hasHistory(),
      canUndoCleanup: createCleanup(vault).hasBatches(),
      goalsChanged,
      goalsBefore: goalsChanged ? baseGoals : null,
      documents: vault.listAttachments(),
      goals: draftGoals,
      toread: readLines(model.toread, /^\s*-\s+/).map((entry) => ({ ...entry, age: ageOf(entry.text) })),
      tags,
      top5: model.top5.map(view),
      urgent: model.urgent.map(view),
      normal: model.normal.map(view),
      parked: (model.parked ?? []).map(view),
      completed: model.completed.map(view),
      deleted: model.deleted.map(view),
    };
  }

  function requireConfigured() {
    if (!configured()) {
      const err = new Error("Choose or create a todo file first.");
      err.code = "NOT_CONFIGURED";
      throw err;
    }
  }

  function requireNoDraft() {
    if (draft) {
      const err = new Error("Apply or discard the assistant draft before making direct edits.");
      err.code = "DRAFT_PENDING";
      throw err;
    }
  }

  function saveDirect(mutator, op = "edit") {
    requireConfigured();
    requireNoDraft();
    if (vault.version() !== baseVersion) {
      reloadBase();
      throw new VaultConflictError();
    }
    const before = base;
    const working = clone(base);
    const description = mutator(working);
    if (!description) return null;
    const saved = vault.save(working, { op, expectedVersion: baseVersion });
    base = assignIds(working);
    baseVersion = saved.version;
    seen = touch(vault, base);
    return applyActivityLog(before, base);
  }

  const json = (res, status, obj) => {
    res.writeHead(status, { "content-type": "application/json" });
    res.end(JSON.stringify(obj));
  };
  const readBody = (req, maxBytes = 1_000_000) => new Promise((resolveBody, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > maxBytes) reject(new Error("request too large"));
    });
    req.on("end", () => {
      try { resolveBody(body ? JSON.parse(body) : {}); } catch { reject(new Error("invalid JSON")); }
    });
  });

  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://${DEFAULT_HOST}`);
      const p = url.pathname;

      if (req.method === "GET" && p === "/") {
        res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
        return res.end(await readFile(join(here, "..", "public", "index.html")));
      }
      if (req.method === "GET" && (p === "/icon-192.png" || p === "/icon-512.png" || p === "/manifest.webmanifest")) {
        try {
          const buf = await readFile(join(here, "..", "public", p.slice(1)));
          res.writeHead(200, { "content-type": p.endsWith(".png") ? "image/png" : "application/manifest+json" });
          return res.end(buf);
        } catch { return json(res, 404, { error: "not found" }); }
      }
      if (req.method === "GET" && p === "/api/model") return json(res, 200, modelView());

      if (req.method === "GET" && p === "/api/memory") {
        requireConfigured();
        return json(res, 200, createMemory(vault).read());
      }

      // User-initiated note creation (their explicit action — immediate, snapshotted).
      if (req.method === "POST" && p === "/api/notes/create") {
        requireConfigured();
        const { name, content } = await readBody(req);
        if (!name?.trim()) return json(res, 400, { error: "A note name is required." });
        const r = createNotes(vault).createNote(name, content ?? "");
        if (r.error) return json(res, 400, { error: r.error });
        return json(res, 200, { ok: true, path: r.path });
      }

      if (req.method === "GET" && p === "/api/notes") {
        requireConfigured();
        const list = createNotes(vault).list().map((n) => n.note);
        let rootEntries = null, subdirs = null, dirError = null;
        try {
          const entries = readdirSync(vault.vaultPath, { withFileTypes: true });
          rootEntries = entries.length;
          subdirs = entries.filter((e) => e.isDirectory() && !e.name.startsWith(".")).length;
        } catch (e) { dirError = e.code || String(e.message || e); }
        return json(res, 200, { notes: list, dir: vault.vaultPath, rootEntries, subdirs, dirError });
      }

      if (req.method === "POST" && p === "/api/config") {
        const { path, mode = "open" } = await readBody(req);
        configurePath(path, mode);
        return json(res, 200, { ok: true, model: modelView() });
      }

      if (req.method === "POST" && p === "/api/pick-file") {
        const { mode = "open" } = await readBody(req);
        if (!["open", "blank", "demo"].includes(mode)) return json(res, 400, { error: "Invalid file action." });
        const path = await filePicker(mode);
        configurePath(path, mode);
        return json(res, 200, { ok: true, path: vault.todoDocPath, model: modelView() });
      }

      if (req.method === "POST" && p === "/api/reload") {
        requireConfigured();
        clearDraft();
        externalConflict = false;
        reloadBase();
        sessionId = undefined;
        return json(res, 200, { ok: true, model: modelView() });
      }

      if (req.method === "POST" && p === "/api/undo") {
        requireConfigured();
        if (busy) return json(res, 409, { error: "The assistant is working. Wait for it to finish.", code: "BUSY" });
        // Undo reverts the last change written to disk; drop any un-applied draft first.
        const result = vault.undo();
        if (!result) return json(res, 400, { error: "Nothing to undo yet." });
        clearDraft();
        externalConflict = false;
        reloadBase();
        return json(res, 200, { ok: true, model: modelView() });
      }

      // Undo the most recent applied vault cleanup batch (moves back, un-trash).
      // Separate from the todo Undo above — they undo different files, and users
      // must not fear that undoing a todo edit un-moves a dozen notes.
      if (req.method === "POST" && p === "/api/cleanup/undo") {
        requireConfigured();
        if (busy) return json(res, 409, { error: "The assistant is working. Wait for it to finish.", code: "BUSY" });
        const r = createCleanup(vault).undoLastBatch();
        if (r.error) return json(res, 400, { error: r.error });
        return json(res, 200, { ok: true, model: modelView(), restored: r.restored, skipped: r.skipped, done: r.done });
      }

      // Start an activity log in linked notes that don't have one yet (the toast's
      // "Start log" — creates the `## Log` section, opting those notes in), and
      // append the pending entries.
      if (req.method === "POST" && p === "/api/activity/enable") {
        requireConfigured();
        const { items } = await readBody(req);
        if (!Array.isArray(items) || !items.length) return json(res, 400, { error: "Nothing to log." });
        const r = createActivity(vault).enable(items);
        if (r.undo.length) lastActivity = { undo: r.undo };
        return json(res, 200, { ok: true, logged: r.logged.map((l) => l.note), model: modelView() });
      }

      // Undo the most recent batch of activity-log appends (the toast's Undo).
      if (req.method === "POST" && p === "/api/activity/undo") {
        requireConfigured();
        if (!lastActivity?.undo?.length) return json(res, 400, { error: "Nothing to undo." });
        const r = createActivity(vault).undo(lastActivity.undo);
        lastActivity = null;
        return json(res, 200, { ok: true, removed: r.removed, model: modelView() });
      }

      if (req.method === "POST" && p === "/api/chat") {
        requireConfigured();
        if (busy) return json(res, 409, { error: "The assistant is already working.", code: "BUSY" });
        refreshFromDisk();
        if (externalConflict) return json(res, 409, conflictBody("The file changed externally. Reload before continuing the draft."));
        const { message } = await readBody(req);
        if (!message?.trim()) return json(res, 400, { error: "Enter a message." });
        // Stream the agent's steps (SSE) when the client asks; otherwise plain JSON.
        const stream = (req.headers.accept || "").includes("text/event-stream");
        const hadPending = !!draft || draftNoteEdits.length > 0;
        let candidate = clone(draft ?? base);
        const startBase = clone(base);      // base as it was when the agent started
        const startVersion = baseVersion;
        const candidateOps = [...draftOps];
        const noteEdits = [...draftNoteEdits];
        busy = true;
        activeAbort = new AbortController();
        const timeout = setTimeout(() => activeAbort?.abort("Assistant request timed out."), 120_000);
        let sse = null;
        if (stream) {
          res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
          sse = (event, data) => { try { res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`); } catch {} };
          sse("start", { ok: true });
        }
        try {
          const before = candidateOps.length;
          const onEvent = stream ? (ev) => sse("step", ev) : undefined;
          const docs = { list: () => vault.listAttachments(), read: (name) => vault.readAttachment(name) };
          const mem = createMemory(vault);
          const notes = createNotes(vault);
          const cleanup = createCleanup(vault);
          const result = await agentRunner({ model: candidate, ops: candidateOps, seen, message, sessionId, abortController: activeAbort, onEvent, docs, mem, notes, cleanup, noteEdits });
          sessionId = result.sessionId;
          chatMessages.push({ role: "you", text: message }, { role: "bot", text: result.reply });
          saveChat(vault.todoDocPath, { sessionId, messages: chatMessages });
          // If a direct edit landed while the assistant was working (e.g. you
          // checked off a todo mid-chat), fold it into the candidate so the
          // assistant's result doesn't revert it.
          if (!hadPending && baseVersion !== startVersion) {
            for (const ch of diffModels(startBase, base)) candidate = applyChangeToBase(candidate, base, ch.key);
          }
          // Small todo-only change sets apply straight to the file; larger ones —
          // or anything touching a note — are held for review (note writes never
          // auto-apply, guardrail).
          let flash = null, applied = false, activity = null;
          const changes = candidateOps.length ? diffModels(base, candidate) : [];
          const anyNote = noteEdits.length > 0;
          if (changes.length && !hadPending && !anyNote && isSmallChangeSet(base, candidate, changes)) {
            const beforeAuto = base;
            const saved = vault.save(candidate, { op: "agent", expectedVersion: baseVersion });
            base = assignIds(candidate);
            baseVersion = saved.version;
            seen = touch(vault, base);
            flash = flashInfo(changes);
            applied = true;
            activity = applyActivityLog(beforeAuto, base);
          } else if (changes.length || anyNote) {
            if (changes.length) {
              draft = candidate;
              draftOps = candidateOps;
              if (!draftBaseVersion) draftBaseVersion = baseVersion;
            }
            draftNoteEdits = noteEdits;
          }
          const payload = { reply: result.reply, model: modelView(), newOps: candidateOps.slice(before), applied, flash, activity };
          if (stream) { sse("done", payload); return res.end(); }
          return json(res, 200, payload);
        } catch (err) {
          if (stream) { sse("error", { error: String(err?.message || err) }); return res.end(); }
          throw err;
        } finally {
          clearTimeout(timeout);
          activeAbort = null;
          busy = false;
        }
      }

      if (req.method === "GET" && p === "/api/chat-history") {
        return json(res, 200, { messages: chatMessages });
      }
      if (req.method === "POST" && p === "/api/chat-clear") {
        chatMessages = [];
        sessionId = undefined;
        if (configured()) saveChat(vault.todoDocPath, { sessionId: undefined, messages: [] });
        return json(res, 200, { ok: true });
      }
      if (req.method === "POST" && p === "/api/cancel") {
        if (!activeAbort) return json(res, 400, { error: "The assistant is not currently working." });
        activeAbort.abort("Cancelled by user.");
        return json(res, 200, { ok: true });
      }

      if (req.method === "POST" && p === "/api/documents") {
        requireConfigured();
        const { name, data } = await readBody(req, UPLOAD_LIMIT);
        if (!name?.trim() || typeof data !== "string") return json(res, 400, { error: "A file name and contents are required." });
        const saved = vault.saveAttachment(name, Buffer.from(data, "base64"));
        return json(res, 200, { ok: true, name: saved, model: modelView() });
      }

      if (req.method === "GET" && p === "/api/documents/file") {
        requireConfigured();
        const name = url.searchParams.get("name") || "";
        const buf = vault.readAttachment(name);
        if (!buf) return json(res, 404, { error: "That document was not found." });
        const safe = name.split(/[\\/]/).pop().replace(/["\r\n]/g, "");
        res.writeHead(200, {
          "content-type": MIME[extname(safe).toLowerCase()] || "application/octet-stream",
          "content-disposition": `inline; filename="${safe}"`,
          "content-length": buf.length,
        });
        return res.end(buf);
      }

      if (req.method === "POST" && p === "/api/documents/remove") {
        requireConfigured();
        const { name } = await readBody(req);
        if (!vault.removeAttachment(name)) return json(res, 404, { error: "That document was not found." });
        return json(res, 200, { ok: true, model: modelView() });
      }

      if (req.method === "POST" && p === "/api/act") {
        const { action, ...args } = await readBody(req);
        if (action === "addToRead") args.text = await unfurlUrl(args.text);
        const activity = saveDirect((working) => applyAction(working, action, args));
        return json(res, 200, { ok: true, model: modelView(), activity });
      }

      // Dumb, agent-free capture path (share sheet, Shortcut, curl): title in,
      // added to Urgent (or Normal), with a server-side near-duplicate note.
      if (req.method === "POST" && p === "/api/capture") {
        requireConfigured();
        requireNoDraft();
        const { title, bucket } = await readBody(req);
        if (!title?.trim()) return json(res, 400, { error: "A title is required." });
        const dup = findDuplicate(base, title);
        const b = bucket === "normal" ? "normal" : "urgent";
        saveDirect((working) => applyAction(working, "add", { title: title.trim(), bucket: b }), "capture");
        return json(res, 200, { ok: true, captured: true, bucket: b, duplicateOf: dup ? dup.title : null });
      }

      if (req.method === "POST" && p === "/api/goals") {
        const { content } = await readBody(req);
        saveDirect((working) => {
          if (!working.goals) working.goals = { headerLine: "## 🎯 Goals", rawLines: [] };
          working.goals.rawLines = String(content ?? "").replace(/\r/g, "").split("\n");
          return "edited Goals";
        });
        return json(res, 200, { ok: true, model: modelView() });
      }

      if (req.method === "POST" && p === "/api/apply") {
        requireConfigured();
        if (!draft && !draftNoteEdits.length) return json(res, 400, { error: "There is nothing to apply." });
        refreshFromDisk();
        if (draft && (externalConflict || vault.version() !== draftBaseVersion)) {
          externalConflict = true;
          return json(res, 409, conflictBody("The file changed after this draft started. Reload and ask the assistant again."));
        }
        let flash = null, activity = null;
        if (draft) {
          flash = flashInfo(diffModels(base, draft));
          const beforeApply = base;
          const saved = vault.save(draft, { op: "agent", expectedVersion: draftBaseVersion });
          base = assignIds(draft);
          baseVersion = saved.version;
          seen = touch(vault, base);
          activity = applyActivityLog(beforeApply, base);
        }
        const { results, keep } = executeIntents(draftNoteEdits);
        // A move/trash whose file changed on disk is skipped and kept staged so
        // the user can re-ask; everything else is done — drop the draft.
        draft = null; draftOps = []; draftBaseVersion = null;
        draftNoteEdits = keep;
        externalConflict = false;
        return json(res, 200, { ok: true, model: modelView(), flash, notes: results, activity });
      }

      if (req.method === "POST" && p === "/api/approve-change") {
        requireConfigured();
        if (!draft && !draftNoteEdits.length) return json(res, 400, { error: "There is no assistant draft." });
        const { key } = await readBody(req);
        if (!key) return json(res, 400, { error: "Which change to approve?" });
        if (key.startsWith("note:")) {
          const i = Number(key.slice(5));
          if (!Number.isInteger(i) || i < 0 || i >= draftNoteEdits.length) return json(res, 400, { error: "No such note change." });
          const { results } = executeIntents([draftNoteEdits[i]]);
          const r = results[0];
          if (r.error || r.skipped) return json(res, 400, { error: r.error || "That change couldn't be applied." });
          draftNoteEdits.splice(i, 1);
          return json(res, 200, { ok: true, model: modelView(), note: r });
        }
        if (!draft) return json(res, 400, { error: "No such change to approve." });
        refreshFromDisk();
        if (externalConflict || vault.version() !== draftBaseVersion) {
          externalConflict = true;
          return json(res, 409, conflictBody("The file changed after this draft started. Reload and ask again."));
        }
        const beforeApprove = base;
        const next = applyChangeToBase(base, draft, key);
        const saved = vault.save(next, { op: "agent", expectedVersion: baseVersion });
        base = assignIds(next);
        baseVersion = saved.version;
        draftBaseVersion = baseVersion;
        seen = touch(vault, base);
        const activity = applyActivityLog(beforeApprove, base);
        if (!diffModels(base, draft).length) { draft = null; draftOps = []; draftBaseVersion = null; }
        const flash = { items: key.startsWith("item:") ? [key.slice(5)] : [], goals: key === "goals", toread: key === "toread" };
        return json(res, 200, { ok: true, model: modelView(), flash, activity });
      }

      if (req.method === "POST" && p === "/api/reject-change") {
        requireConfigured();
        if (!draft && !draftNoteEdits.length) return json(res, 400, { error: "There is no assistant draft." });
        const { key } = await readBody(req);
        if (!key) return json(res, 400, { error: "Which change to reject?" });
        if (key.startsWith("note:")) {
          const i = Number(key.slice(5));
          if (Number.isInteger(i) && i >= 0 && i < draftNoteEdits.length) draftNoteEdits.splice(i, 1);
        } else if (draft) {
          refreshFromDisk();
          if (externalConflict) return json(res, 409, conflictBody("The file changed externally. Reload before editing the draft."));
          rejectChangeOn(base, draft, key);
          // Todo draft no longer differs from base → drop it (note edits stay).
          if (!diffModels(base, draft).length) { draft = null; draftOps = []; draftBaseVersion = null; }
        }
        return json(res, 200, { ok: true, model: modelView() });
      }

      if (req.method === "POST" && p === "/api/discard") {
        requireConfigured();
        clearDraft();
        externalConflict = false;
        refreshFromDisk();
        return json(res, 200, { ok: true, model: modelView() });
      }
      return json(res, 404, { error: "not found" });
    } catch (error) {
      if (error instanceof VaultConflictError || error?.code === "VAULT_CONFLICT") {
        if (draft) externalConflict = true;
        return json(res, 409, conflictBody(error.message));
      }
      if (error?.message === "request too large") return json(res, 413, { error: "That file is too large (about 30 MB maximum)." });
      const clientCodes = new Set(["NOT_CONFIGURED", "PICKER_CANCELLED", "PICKER_UNAVAILABLE", "FILE_NOT_FOUND", "FILE_EXISTS"]);
      const status = error?.code === "DRAFT_PENDING" || error?.code === "FILE_EXISTS" ? 409 : clientCodes.has(error?.code) ? 400 : 500;
      if (status === 500) console.error(error);
      return json(res, status, { error: String(error?.message || error), code: error?.code });
    }
  });

  const bootPath = initialTodoDocPath && existsSync(expandPath(initialTodoDocPath)) ? initialTodoDocPath : recallFile();
  if (bootPath) { try { setVault(bootPath); } catch (e) { console.error("Could not reopen last file:", e.message); } }
  return server;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = createBigRocksServer();
  server.listen(DEFAULT_PORT, DEFAULT_HOST, () => {
    console.log(`Big Rocks First — http://${DEFAULT_HOST}:${DEFAULT_PORT}`);
    console.log(process.env.TODO_FILE ? `vault doc: ${expandPath(process.env.TODO_FILE)}` : "Open the browser to choose or create a todo file.");
  });
}
