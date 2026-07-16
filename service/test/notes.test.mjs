import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createNotes } from "../src/notes.mjs";

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "bigrocks-vault-"));
  writeFileSync(join(root, "todo.md"), "# Todo\n");
  writeFileSync(join(root, "Assistant Memory.md"), "# Assistant Memory\n");
  writeFileSync(join(root, "Team Notes.md"), "# Team Notes\n\nThe vendor quote was $4,000.\nSee [[Roadmap]].\n");
  mkdirSync(join(root, "projects"));
  writeFileSync(join(root, "projects", "Roadmap.md"), "# Roadmap\n\nLaunch is in Q3.\n");
  mkdirSync(join(root, ".obsidian"));
  writeFileSync(join(root, ".obsidian", "config"), "should be skipped");
  mkdirSync(join(root, ".bigrocks"));
  writeFileSync(join(root, ".bigrocks", "seen.json"), "{}");
  const vault = { vaultPath: root, todoDocPath: join(root, "todo.md"), memoryPath: join(root, "Assistant Memory.md") };
  return { root, notes: createNotes(vault) };
}

test("list excludes the todo doc, memory note, and dotfolders — with dates", () => {
  const f = fixture();
  try {
    const list = f.notes.list();
    const paths = list.map((n) => n.note);
    assert.ok(paths.includes("Team Notes.md"));
    assert.ok(paths.includes(join("projects", "Roadmap.md")));
    assert.ok(!paths.includes("todo.md"));
    assert.ok(!paths.includes("Assistant Memory.md"));
    assert.ok(!paths.some((p) => p.includes(".obsidian") || p.includes(".bigrocks")));
    assert.match(list[0].created, /^\d{4}-\d{2}-\d{2}$/, "each note carries a created date");
    assert.match(list[0].modified, /^\d{4}-\d{2}-\d{2}$/);
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("read resolves a [[wikilink]] name (even in a subfolder) and a full path", () => {
  const f = fixture();
  try {
    assert.match(f.notes.read("[[Roadmap]]").content, /Launch is in Q3/);
    assert.match(f.notes.read("Team Notes").content, /vendor quote/);
    assert.match(f.notes.read(join("projects", "Roadmap.md")).content, /Launch is in Q3/);
    assert.ok(f.notes.read("does-not-exist").error);
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("read refuses path traversal outside the vault", () => {
  const f = fixture();
  try {
    assert.ok(f.notes.read("../../../etc/hosts").error);
    assert.ok(f.notes.read("/etc/hosts").error);
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("search finds matching lines with note + line number", () => {
  const f = fixture();
  try {
    const hits = f.notes.search("vendor");
    assert.equal(hits.length, 1);
    assert.equal(hits[0].note, "Team Notes.md");
    assert.match(hits[0].text, /vendor quote/);
    assert.deepEqual(f.notes.search(""), []);
    assert.deepEqual(f.notes.search("nothing-matches-xyz"), []);
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});
