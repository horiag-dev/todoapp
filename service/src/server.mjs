import { createServer } from "node:http";
import { existsSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { Vault, VaultConflictError } from "./vault.mjs";
import { assignIds, itemView } from "./model.mjs";
import { runAgent } from "./agent.mjs";
import { touch, ageDays } from "./ledger.mjs";
import { applyAction } from "./ops.mjs";

const here = dirname(fileURLToPath(import.meta.url));
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
  let externalConflict = false;
  let sessionId;
  let chatMessages = [];
  let busy = false;
  let activeAbort = null;

  function configured() {
    return !!vault;
  }

  function setVault(todoDocPath) {
    vault = new Vault({ todoDocPath: expandPath(todoDocPath) });
    reloadBase();
    draft = null;
    draftOps = [];
    draftBaseVersion = null;
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
    if (!configured()) return { configured: false, busy };
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
    return {
      configured: true,
      todoDocPath: vault.todoDocPath,
      version: baseVersion,
      dirty: !!draft,
      ops: draftOps,
      conflict: externalConflict,
      busy,
      goals: model.goals?.rawLines ?? [],
      toread: readLines(model.toread, /^\s*-\s+/).map((entry) => ({ ...entry, age: ageOf(entry.text) })),
      tags,
      top5: model.top5.map(view),
      urgent: model.urgent.map(view),
      normal: model.normal.map(view),
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
    const working = clone(base);
    const description = mutator(working);
    if (!description) return;
    const saved = vault.save(working, { op, expectedVersion: baseVersion });
    base = assignIds(working);
    baseVersion = saved.version;
    seen = touch(vault, base);
  }

  const json = (res, status, obj) => {
    res.writeHead(status, { "content-type": "application/json" });
    res.end(JSON.stringify(obj));
  };
  const readBody = (req) => new Promise((resolveBody, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1_000_000) reject(new Error("request too large"));
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
      if (req.method === "GET" && p === "/api/model") return json(res, 200, modelView());

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
        draft = null;
        draftOps = [];
        draftBaseVersion = null;
        externalConflict = false;
        reloadBase();
        sessionId = undefined;
        return json(res, 200, { ok: true, model: modelView() });
      }

      if (req.method === "POST" && p === "/api/chat") {
        requireConfigured();
        if (busy) return json(res, 409, { error: "The assistant is already working.", code: "BUSY" });
        refreshFromDisk();
        if (externalConflict) return json(res, 409, conflictBody("The file changed externally. Reload before continuing the draft."));
        const { message } = await readBody(req);
        if (!message?.trim()) return json(res, 400, { error: "Enter a message." });
        const candidate = clone(draft ?? base);
        const candidateOps = [...draftOps];
        busy = true;
        activeAbort = new AbortController();
        const timeout = setTimeout(() => activeAbort?.abort("Assistant request timed out."), 120_000);
        try {
          const before = candidateOps.length;
          const result = await agentRunner({ model: candidate, ops: candidateOps, seen, message, sessionId, abortController: activeAbort });
          sessionId = result.sessionId;
          chatMessages.push({ role: "you", text: message }, { role: "bot", text: result.reply });
          saveChat(vault.todoDocPath, { sessionId, messages: chatMessages });
          draft = candidateOps.length ? candidate : draft;
          draftOps = candidateOps;
          if (draft && !draftBaseVersion) draftBaseVersion = baseVersion;
          return json(res, 200, { reply: result.reply, model: modelView(), newOps: candidateOps.slice(before) });
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

      if (req.method === "POST" && p === "/api/act") {
        const { action, ...args } = await readBody(req);
        saveDirect((working) => applyAction(working, action, args));
        return json(res, 200, { ok: true, model: modelView() });
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
        if (!draft) return json(res, 400, { error: "There is no assistant draft to apply." });
        refreshFromDisk();
        if (externalConflict || vault.version() !== draftBaseVersion) {
          externalConflict = true;
          return json(res, 409, conflictBody("The file changed after this draft started. Reload and ask the assistant again."));
        }
        const saved = vault.save(draft, { op: "agent", expectedVersion: draftBaseVersion });
        base = assignIds(draft);
        baseVersion = saved.version;
        draft = null;
        draftOps = [];
        draftBaseVersion = null;
        externalConflict = false;
        seen = touch(vault, base);
        return json(res, 200, { ok: true, model: modelView() });
      }

      if (req.method === "POST" && p === "/api/discard") {
        requireConfigured();
        draft = null;
        draftOps = [];
        draftBaseVersion = null;
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
