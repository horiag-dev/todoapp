// Vault Module 3 (careful reorganization): survey the vault read-only, then STAGE
// moves and recoverable trashes into the same reviewed-change pipeline that note
// appends use. Nothing touches disk until the user approves in the review panel.
//
// Prime directive: the user sees exactly what will happen before it happens, and
// can recover anything afterward. So — no hard deletes (trash is a move into
// .bigrocks/trash), every applied batch is recorded in a manifest for one-click
// undo, preconditions are checked at apply time (a cloud-sync mid-review can't
// corrupt anything), and the protected set (todo doc, memory, .obsidian, …) is
// refused at BOTH stage and execute time — staging checks are for good UX, the
// execute-time checks are the actual safety boundary.
import {
  readFileSync, existsSync, statSync, mkdirSync, renameSync, rmSync, copyFileSync, readdirSync, realpathSync,
} from "node:fs";
import { join, resolve, relative, dirname, basename, extname, sep } from "node:path";
import { createHash } from "node:crypto";
import { createNotes, TEXT_EXT, SKIP_DIRS } from "./notes.mjs";
import { writeFileAtomic } from "./fsAtomic.mjs";

const MAX_PLAN_OPS = 30; // staged cleanup ops (move/trash) per draft

const stampTs = () => new Date().toISOString().replace(/[:.]/g, "-");
const normLink = (t) => basename(String(t ?? "").trim()).replace(/\.md$/i, "").toLowerCase();
const normTitle = (s) => String(s ?? "").toLowerCase()
  .replace(/\((?:copy|copie)\)/g, " ").replace(/\bcopy\b/g, " ")
  .replace(/\s+\d+$/, "").replace(/[^a-z0-9]+/g, " ").trim();

export function createCleanup(vault) {
  const root = vault.vaultPath;
  const notes = createNotes(vault);
  const cleanupDir = join(vault.machineDir, "cleanup");
  const trashRoot = join(vault.machineDir, "trash");

  // Canonical path: resolves symlinks AND real on-disk casing (macOS APFS is
  // case-insensitive by default, so "Todo.md" and "todo.md" are the SAME file
  // — but plain string compare says otherwise). Falls back to a lexical resolve
  // when the path doesn't exist yet (e.g. a not-yet-created move destination).
  const canon = (p) => { try { return realpathSync.native(resolve(p)); } catch { return resolve(p); } };
  const realRoot = canon(root);
  // The protected files, both canonically (symlink+case correct when they exist)
  // and case-folded (a belt for the rare case realpath can't resolve them). No
  // real note is ever named an alternate-case spelling of the todo doc / memory
  // note, so the case-folded set has no meaningful false-positive risk.
  const protectedCanon = new Set([canon(vault.todoDocPath), canon(vault.memoryPath)]);
  const protectedLower = new Set([resolve(vault.todoDocPath).toLowerCase(), resolve(vault.memoryPath).toLowerCase()]);
  const isProtectedFile = (full) => protectedCanon.has(canon(full)) || protectedLower.has(resolve(full).toLowerCase());

  // Containment that survives symlinks: resolve the nearest EXISTING ancestor
  // (the target itself may not exist yet) to its real path, then check the whole
  // thing stays under the real vault root. A subfolder that is a symlink pointing
  // outside the vault is therefore refused — withinRoot is THE boundary.
  const withinRoot = (p) => {
    const target = resolve(p);
    let anc = target;
    while (!existsSync(anc) && dirname(anc) !== anc) anc = dirname(anc);
    let realAnc; try { realAnc = realpathSync.native(anc); } catch { realAnc = anc; }
    const rem = relative(anc, target);
    const full = rem ? join(realAnc, rem) : realAnc;
    return full === realRoot || full.startsWith(realRoot + sep);
  };
  const abs = (rel) => resolve(root, rel);
  const hashOf = (full) => createHash("sha256").update(readFileSync(full)).digest("hex");
  const stemOf = (rel) => basename(rel).replace(/\.md$/i, "");

  // Reuse the notes module's file list (already excludes todo/memory/dotfolders).
  // Cached per instance: staging never writes, so within a chat turn it's stable.
  let _files = null;
  const noteFiles = () => (_files ??= notes.list().map((n) => abs(n.note)));

  // One pass over all notes → inbound reference counts (by normalized basename)
  // and per-file outbound counts. Cheap at ~hundreds of notes; never persisted.
  let _index = null;
  function linkIndex() {
    if (_index) return _index;
    const inbound = new Map();   // normbasename -> Set(referring absolute paths)
    const outbound = new Map();  // absolute path -> count
    const wl = /\[\[([^\]]+?)\]\]/g, md = /\]\(([^)]+?\.md)\)/gi;
    for (const f of noteFiles()) {
      let txt; try { txt = readFileSync(f, "utf8"); } catch { continue; }
      let m, count = 0;
      wl.lastIndex = 0;
      while ((m = wl.exec(txt))) {
        const key = normLink(m[1].split("|")[0].split("#")[0]);
        if (!key) continue;
        count++;
        (inbound.get(key) ?? inbound.set(key, new Set()).get(key)).add(f);
      }
      md.lastIndex = 0;
      while ((m = md.exec(txt))) {
        let raw; try { raw = decodeURIComponent(m[1]); } catch { raw = m[1]; }
        const key = normLink(raw);
        if (!key) continue;
        count++;
        (inbound.get(key) ?? inbound.set(key, new Set()).get(key)).add(f);
      }
      outbound.set(f, count);
    }
    return (_index = { inbound, outbound });
  }
  const inboundCount = (rel) => {
    const refs = linkIndex().inbound.get(normLink(basename(rel)));
    if (!refs) return 0;
    const self = abs(rel);
    return [...refs].filter((f) => f !== self).length;
  };

  const isEmpty = (txt) => {
    const body = String(txt ?? "").replace(/^﻿/, "").trim();
    if (!body) return true;
    const lines = body.split("\n").map((l) => l.trim()).filter(Boolean);
    return lines.length === 1 && /^#{1,6}\s/.test(lines[0]); // a lone title heading
  };
  const daysSince = (iso) => {
    if (!iso) return 0;
    const t = Date.parse(iso);
    return Number.isFinite(t) ? Math.floor((Date.now() - t) / 86400000) : 0;
  };

  const resolveSource = (p) => {
    const cleaned = String(p ?? "").replace(/^\[\[|\]\]$/g, "").split("|")[0].trim();
    if (!cleaned) return null;
    for (const cand of [resolve(root, cleaned), resolve(root, /\.\w+$/.test(cleaned) ? cleaned : `${cleaned}.md`)])
      if (withinRoot(cand) && existsSync(cand) && statSync(cand).isFile()) return cand;
    return null;
  };

  // Shared by every stage validator AND re-run at execute. `rel` is vault-relative.
  function assertOperable(rel, { mustExist = true } = {}) {
    const full = resolve(root, rel);
    if (!withinRoot(full)) return { error: `"${rel}" is outside the vault.` };
    const r = relative(root, full);
    const segs = r.split(sep);
    if (segs.some((s) => s.startsWith("."))) return { error: `Refusing a hidden/system path (${r}).` };
    // Case-insensitive: on macOS "Attachments" IS the reserved attachments folder.
    if (segs.some((s) => SKIP_DIRS.has(s.toLowerCase()))) return { error: `Refusing a protected folder (${r}).` };
    if (isProtectedFile(full)) return { error: `"${r}" is protected (your todo list or Assistant Memory) — never moved or trashed.` };
    if (!TEXT_EXT.has(extname(full).toLowerCase())) return { error: `Only note/text files can be reorganized, not "${r}".` };
    if (mustExist && !(existsSync(full) && statSync(full).isFile())) return { error: `No note at "${r}".` };
    return { full, rel: r };
  }

  // Trim a leading "./" or "/" (agents sometimes pass those) and any trailing
  // slash — but DON'T strip a bare leading dot, so ".obsidian"/".git" stay
  // dot-prefixed and get refused by assertOperable instead of silently becoming
  // ordinary folders. A genuine "../.." traversal is left intact to be caught by
  // the withinRoot check.
  const normalizeFolder = (folder) => String(folder ?? "").replace(/^(?:\.?\/)+/, "").replace(/\/+$/, "").trim();

  // Notes that link to `rel` by a FOLDER PATH (e.g. [[Inbox/Foo]] or (Inbox/Foo.md)).
  // Bare [[wikilinks]] survive a move (Obsidian resolves by name); path-style ones break.
  function pathStyleReferrers(rel) {
    const base = normLink(basename(rel));
    const me = abs(rel);
    const wl = /\[\[([^\]]+?)\]\]/g, md = /\]\(([^)]+?\.md)\)/gi;
    const hits = [];
    for (const f of noteFiles()) {
      if (f === me) continue;
      let txt; try { txt = readFileSync(f, "utf8"); } catch { continue; }
      let hit = false, m;
      wl.lastIndex = 0;
      while ((m = wl.exec(txt))) {
        const raw = m[1].split("|")[0].split("#")[0].trim();
        if (raw.includes("/") && normLink(raw) === base) { hit = true; break; }
      }
      if (!hit) { md.lastIndex = 0; while ((m = md.exec(txt))) {
        let raw; try { raw = decodeURIComponent(m[1]); } catch { raw = m[1]; }
        if (raw.includes("/") && normLink(raw) === base) { hit = true; break; }
      } }
      if (hit) hits.push(relative(root, f));
    }
    return hits;
  }

  const countStaged = (staged) => (staged ?? []).filter((e) => e.op === "move" || e.op === "trash").length;

  // --- Read-only planning ----------------------------------------------------
  function overview(folder) {
    const scope = normalizeFolder(folder);
    const inScope = (rel) => !scope || rel === scope || rel.startsWith(scope + sep) || dirname(rel) === scope;
    const list = notes.list().filter((n) => inScope(n.note));
    const tree = {}, out = [];
    for (const n of list) {
      const full = abs(n.note);
      let bytes = 0, content = "";
      try { bytes = statSync(full).size; } catch {}
      try { content = readFileSync(full, "utf8"); } catch {}
      const dir = dirname(n.note) === "." ? "" : dirname(n.note);
      tree[dir] = (tree[dir] || 0) + 1;
      const inb = inboundCount(n.note);
      out.push({
        note: n.note, created: n.created, modified: n.modified, bytes,
        inboundLinks: inb, outboundLinks: linkIndex().outbound.get(full) || 0,
        empty: isEmpty(content),
        staleCandidate: daysSince(n.modified) > 365 && inb === 0,
      });
    }
    return { tree, notes: out, protected: [relative(root, vault.todoDocPath), relative(root, vault.memoryPath)] };
  }

  function duplicates() {
    const byHash = new Map(), byTitle = new Map();
    for (const n of notes.list()) {
      let txt; try { txt = readFileSync(abs(n.note), "utf8"); } catch { continue; }
      const h = createHash("sha256").update(txt.replace(/\s+$/, "")).digest("hex");
      (byHash.get(h) ?? byHash.set(h, []).get(h)).push(n.note);
      const t = normTitle(stemOf(n.note));
      if (t) (byTitle.get(t) ?? byTitle.set(t, []).get(t)).push(n.note);
    }
    const exact = [...byHash.values()].filter((g) => g.length > 1);
    const exactSet = new Set(exact.flat());
    // A title-variant group is only interesting if it isn't already an exact dupe.
    const titleVariants = [...byTitle.values()]
      .filter((g) => g.length > 1 && g.some((p) => !exactSet.has(p)));
    return { exact, titleVariants };
  }

  // --- Staging validators (return {intent} or {error}; nothing is written) ----
  function stageMove({ path, to_folder, reason }, staged) {
    if (countStaged(staged) >= MAX_PLAN_OPS)
      return { error: `This plan is already at ${MAX_PLAN_OPS} operations — apply this batch first, then continue.` };
    const src = resolveSource(path);
    if (!src) return { error: `No note at "${path}". Use exact paths from vault_overview.` };
    const srcRel = relative(root, src);
    const ok = assertOperable(srcRel);
    if (ok.error) return ok;
    const folder = normalizeFolder(to_folder);
    const destRel = folder ? join(folder, basename(srcRel)) : basename(srcRel);
    const destChk = assertOperable(destRel, { mustExist: false });
    if (destChk.error) return { error: destChk.error };
    if (destRel === srcRel || dirname(srcRel) === (folder || "."))
      return { error: `“${stemOf(srcRel)}” is already in ${folder || "the root"}.` };
    if (existsSync(abs(destRel))) return { error: `A note already exists at ${destRel} — pick another folder or rename first.` };
    const pathRefs = pathStyleReferrers(srcRel);
    if (pathRefs.length)
      return { error: `${pathRefs.length} note${pathRefs.length === 1 ? "" : "s"} link to “${stemOf(srcRel)}” by folder path (${pathRefs.slice(0, 3).join(", ")}${pathRefs.length > 3 ? "…" : ""}). Moving would break those links — rename it in Obsidian instead (Obsidian updates path links itself), or drop this move.` };
    const newFolder = folder && !existsSync(abs(folder));
    return { intent: {
      op: "move", path: srcRel, to: destRel, reason: String(reason ?? "").trim(),
      base: { hash: hashOf(src), mtimeMs: statSync(src).mtimeMs },
      kind: "note-move",
      label: `Move “${stemOf(srcRel)}” → ${folder || "root"}${newFolder ? " (new folder)" : ""}`,
    } };
  }

  function stageTrash({ path, reason, force_linked_ok }, staged) {
    if (countStaged(staged) >= MAX_PLAN_OPS)
      return { error: `This plan is already at ${MAX_PLAN_OPS} operations — apply this batch first, then continue.` };
    const src = resolveSource(path);
    if (!src) return { error: `No note at "${path}". Use exact paths from vault_overview.` };
    const srcRel = relative(root, src);
    const ok = assertOperable(srcRel);
    if (ok.error) return ok;
    let content = ""; try { content = readFileSync(src, "utf8"); } catch {}
    if (/#keep\b/.test(content))
      return { error: `“${stemOf(srcRel)}” is tagged #keep — I won't trash it. Remove the tag first if you really mean to.` };
    const inb = inboundCount(srcRel);
    if (inb > 0 && !force_linked_ok)
      return { error: `${inb} note${inb === 1 ? "" : "s"} link to “${stemOf(srcRel)}” — trashing it would leave broken links. Tell the user, and pass force_linked_ok if they still want it gone.` };
    const rsn = String(reason ?? "").trim();
    return { intent: {
      op: "trash", path: srcRel, reason: rsn,
      base: { hash: hashOf(src), mtimeMs: statSync(src).mtimeMs },
      kind: "note-trash", forced: inb > 0,
      label: `Trash “${stemOf(srcRel)}”${rsn ? ` — ${rsn}` : ""} (recoverable)${inb > 0 ? ` ⚠ ${inb} link${inb === 1 ? "" : "s"}` : ""}`,
    } };
  }

  // --- Apply-time execution (validate again → do it → record in the batch) ----
  function moveFile(src, dest) {
    try { renameSync(src, dest); return; }
    catch (e) {
      if (e.code !== "EXDEV") throw e;
      // Cross-device (some cloud mounts): copy, verify byte-identical, then remove.
      copyFileSync(src, dest);
      if (hashOf(dest) === hashOf(src)) rmSync(src, { force: true });
      else { rmSync(dest, { force: true }); throw e; }
    }
  }

  function execute(intent, batch) {
    const chk = assertOperable(intent.path);
    if (chk.error) return { skipped: true, error: chk.error };
    const src = abs(intent.path);
    if (hashOf(src) !== intent.base?.hash)
      return { skipped: true, error: `“${stemOf(intent.path)}” changed on disk since it was proposed — re-ask the assistant.` };
    if (intent.op === "move") {
      // Re-validate the destination here too — execute time is the real boundary,
      // not stage time (the intent could be stale or the tree could have changed).
      const destChk = assertOperable(intent.to, { mustExist: false });
      if (destChk.error) return { skipped: true, error: destChk.error };
      const dest = abs(intent.to);
      if (existsSync(dest)) return { skipped: true, error: `Something already exists at ${intent.to}.` };
      mkdirSync(dirname(dest), { recursive: true });
      moveFile(src, dest);
      batch.ops.push({ op: "move", from: intent.path, to: intent.to });
      persist(batch); // record BEFORE returning so a crash after this op is still undoable
      return { path: intent.to, moved: true };
    }
    if (intent.op === "trash") {
      const dest = join(trashRoot, batch.ts, intent.path);
      mkdirSync(dirname(dest), { recursive: true });
      moveFile(src, dest);
      batch.ops.push({ op: "trash", from: intent.path, trashedTo: relative(root, dest) });
      persist(batch);
      return { path: intent.path, trashed: true };
    }
    return { skipped: true, error: `Unknown cleanup op “${intent.op}”.` };
  }

  const openBatch = () => ({ ts: stampTs(), ops: [] });
  // Write the manifest reflecting every op done SO FAR. Called after each op
  // (so a crash mid-batch still leaves an undoable record) and again at close.
  // Atomic, so the file is never half-written. An empty batch writes nothing.
  function persist(batch) {
    if (!batch?.ops.length) return null;
    mkdirSync(cleanupDir, { recursive: true });
    const file = join(cleanupDir, `${batch.ts}.json`);
    writeFileAtomic(file, JSON.stringify({ at: new Date().toISOString(), ops: batch.ops }, null, 2));
    return file;
  }
  const closeBatch = (batch) => persist(batch);

  function manifests() {
    try { return readdirSync(cleanupDir).filter((f) => f.endsWith(".json")).sort(); }
    catch { return []; }
  }
  const hasBatches = () => manifests().length > 0;

  function undoLastBatch() {
    const files = manifests();
    if (!files.length) return { error: "No cleanup to undo." };
    const name = files[files.length - 1];
    let manifest;
    try { manifest = JSON.parse(readFileSync(join(cleanupDir, name), "utf8")); }
    catch { return { error: "Could not read the last cleanup record." }; }
    const results = [];
    for (const op of [...manifest.ops].reverse()) {
      try {
        const from = abs(op.from);
        const src = op.op === "trash" ? abs(op.trashedTo) : abs(op.to);
        if (existsSync(from)) { results.push({ op, skipped: true, error: "The original location is occupied." }); continue; }
        if (!existsSync(src)) { results.push({ op, skipped: true, error: "The file is no longer where it was left." }); continue; }
        mkdirSync(dirname(from), { recursive: true });
        moveFile(src, from);
        results.push({ op, restored: true });
      } catch (e) { results.push({ op, skipped: true, error: String(e?.message || e) }); }
    }
    const done = results.every((r) => r.restored);
    if (done) rmSync(join(cleanupDir, name), { force: true });
    return {
      ok: true, done, batch: name,
      restored: results.filter((r) => r.restored).length,
      skipped: results.filter((r) => r.skipped).length,
      details: results,
    };
  }

  return {
    overview, duplicates,
    stageMove, stageTrash,
    execute, openBatch, closeBatch,
    hasBatches, undoLastBatch,
  };
}
