// Vault Module 2 (read-only): let the assistant read and search the user's other
// notes in the vault — the folder around the todo doc. No writes, no indexing;
// plain filesystem reads with path-safety and caps. Follows [[wikilink]] names.
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative, extname, basename, resolve, sep } from "node:path";

const TEXT_EXT = new Set([".md", ".markdown", ".txt", ".text", ".org"]);
const SKIP_DIRS = new Set([".bigrocks", ".obsidian", ".git", ".trash", "node_modules", "attachments"]);
const MAX_FILES = 3000, MAX_READ = 200_000, MAX_HITS = 40;

function walk(dir, out) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (out.length >= MAX_FILES) return;
    if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name) && !e.name.startsWith(".")) walk(join(dir, e.name), out); }
    else if (e.isFile() && TEXT_EXT.has(extname(e.name).toLowerCase())) out.push(join(dir, e.name));
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
  };
}
