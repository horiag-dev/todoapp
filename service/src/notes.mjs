// Vault Module 2 (read-only): let the assistant read and search the user's other
// notes in the vault — the folder around the todo doc. No writes, no indexing;
// plain filesystem reads with path-safety and caps. Follows [[wikilink]] names.
import { readFileSync, readdirSync, statSync, existsSync, mkdirSync, copyFileSync, rmSync } from "node:fs";
import { join, relative, extname, basename, resolve, sep, dirname } from "node:path";
import { writeFileAtomic } from "./fsAtomic.mjs";

// Shared with cleanup.mjs so read, write, and reorganize all agree on which
// files are notes and which folders are off-limits.
export const TEXT_EXT = new Set([".md", ".markdown", ".txt", ".text", ".org"]);
export const SKIP_DIRS = new Set([".bigrocks", ".obsidian", ".git", ".trash", "node_modules", "attachments"]);
const MAX_FILES = 3000, MAX_READ = 200_000, MAX_HITS = 40;

function walk(dir, out) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (out.length >= MAX_FILES) return;
    const full = join(dir, e.name);
    let isDir = e.isDirectory(), isFile = e.isFile();
    // On Dropbox/iCloud (CloudStorage) folders, entries can come back as
    // symlinks / cloud placeholders — neither file nor dir. Stat to resolve
    // (stat doesn't download the file, just reads metadata).
    if (!isDir && !isFile) {
      try { const s = statSync(full); isDir = s.isDirectory(); isFile = s.isFile(); } catch { continue; }
    }
    if (isDir) { if (!SKIP_DIRS.has(e.name) && !e.name.startsWith(".")) walk(full, out); }
    else if (isFile && TEXT_EXT.has(extname(e.name).toLowerCase())) out.push(full);
  }
}

export function createNotes(vault) {
  const root = vault.vaultPath;
  const excluded = new Set([vault.todoDocPath, vault.memoryPath]);
  const withinRoot = (p) => { const r = resolve(p); return r === root || r.startsWith(root + sep); };
  const listFiles = () => { const out = []; walk(root, out); return out.filter((f) => !excluded.has(f)); };

  const resolveNote = (name) => {
    const n = String(name ?? "").replace(/^\[\[|\]\]$/g, "").split("|")[0].trim();
    if (!n) return null;
    for (const cand of [resolve(root, n), resolve(root, n.endsWith(".md") ? n : `${n}.md`)])
      if (withinRoot(cand) && existsSync(cand) && statSync(cand).isFile() && !excluded.has(cand)) return cand;
    const want = basename(n).toLowerCase().replace(/\.md$/, "");
    const hits = listFiles().filter((f) => basename(f).toLowerCase().replace(/\.(md|markdown|txt|text|org)$/, "") === want);
    if (hits.length === 1) return hits[0];
    if (hits.length > 1) return { ambiguous: hits.map((f) => relative(root, f)) };
    return null;
  };

  // When was the note created / last changed? macOS keeps birthtime; fall back to
  // mtime. Surfaced so the assistant can weigh recency (an old note may be stale).
  const stampOf = (f) => {
    try {
      const s = statSync(f);
      const created = s.birthtimeMs && s.birthtimeMs > 0 ? s.birthtimeMs : s.mtimeMs;
      return { created: new Date(created).toISOString().slice(0, 10), modified: new Date(s.mtimeMs).toISOString().slice(0, 10) };
    } catch { return { created: null, modified: null }; }
  };

  return {
    // Most-recently-changed first, each with its created/modified date.
    list() {
      return listFiles()
        .map((f) => ({ note: relative(root, f), ...stampOf(f) }))
        .sort((a, b) => (b.modified || "").localeCompare(a.modified || ""));
    },
    read(name) {
      const r = resolveNote(name);
      if (!r) return { error: `No note found for "${name}". Use list_notes to see what exists.` };
      if (r.ambiguous) return { error: `"${name}" matches several notes: ${r.ambiguous.join(", ")}. Use the full path.` };
      try {
        const txt = readFileSync(r, "utf8");
        return { path: relative(root, r), ...stampOf(r), content: txt.length > MAX_READ ? `${txt.slice(0, MAX_READ)}\n…[truncated]` : txt };
      } catch { return { error: `Could not read "${name}".` }; }
    },
    search(query) {
      const q = String(query ?? "").toLowerCase().trim();
      if (!q) return [];
      const hits = [];
      for (const f of listFiles()) {
        if (hits.length >= MAX_HITS) break;
        let txt;
        try { txt = readFileSync(f, "utf8"); } catch { continue; }
        if (txt.length > MAX_READ) txt = txt.slice(0, MAX_READ);
        const lines = txt.split("\n");
        for (let i = 0; i < lines.length && hits.length < MAX_HITS; i++)
          if (lines[i].toLowerCase().includes(q)) hits.push({ note: relative(root, f), line: i + 1, text: lines[i].trim().slice(0, 200) });
      }
      return hits;
    },
    // --- Writes (called at Apply time; every write is snapshotted) -------------
    appendToNote(name, content) {
      const r = resolveNote(name);
      if (r && r.ambiguous) return { error: `"${name}" matches several notes — use the full path.` };
      const path = r && !r.ambiguous ? r : safeNewPath(name);
      if (!path) return { error: `Invalid note name "${name}".` };
      snapshotNote(path);
      mkdirSync(dirname(path), { recursive: true });
      const existing = existsSync(path) ? readFileSync(path, "utf8").replace(/\s+$/, "") : "";
      const body = String(content ?? "").replace(/\s+$/, "");
      writeFileAtomic(path, (existing ? existing + "\n\n" : "") + body + "\n");
      return { path: relative(root, path) };
    },
    createNote(name, content) {
      const path = safeNewPath(name);
      if (!path) return { error: `Invalid note name "${name}".` };
      if (existsSync(path)) return { error: `"${name}" already exists — append to it instead.` };
      mkdirSync(dirname(path), { recursive: true });
      writeFileAtomic(path, String(content ?? "").replace(/\s+$/, "") + "\n");
      return { path: relative(root, path) };
    },
  };

  function safeNewPath(name) {
    const n = String(name ?? "").replace(/^\[\[|\]\]$/g, "").split("|")[0].trim();
    if (!n) return null;
    const p = resolve(root, /\.\w+$/.test(n) ? n : `${n}.md`);
    return withinRoot(p) && !excluded.has(p) ? p : null;
  }
  function snapshotNote(path) {
    if (!existsSync(path)) return;
    const dir = join(vault.machineDir || join(root, ".bigrocks"), "note-history");
    mkdirSync(dir, { recursive: true });
    const ts = new Date().toISOString().replace(/[:.]/g, "-");
    copyFileSync(path, join(dir, `${ts}__${basename(path)}`));
    try { for (const old of readdirSync(dir).filter((f) => f.endsWith(".md")).sort().slice(0, -40)) rmSync(join(dir, old), { force: true }); } catch {}
  }
}
