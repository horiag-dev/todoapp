import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
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

test("appendToNote appends (creating if missing) and snapshots; createNote makes new", () => {
  const f = fixture();
  try {
    // append to an existing note
    let r = f.notes.appendToNote("Team Notes", "- New action item");
    assert.equal(r.path, "Team Notes.md");
    const teamPath = join(f.root, "Team Notes.md");
    assert.match(readFileSync(teamPath, "utf8"), /vendor quote[\s\S]*New action item/);
    assert.ok(existsSync(join(f.root, ".bigrocks", "note-history")), "prior version snapshotted");

    // append to a non-existent note creates it
    r = f.notes.appendToNote("Brand New", "hello");
    assert.equal(r.path, "Brand New.md");
    assert.match(readFileSync(join(f.root, "Brand New.md"), "utf8"), /hello/);

    // create refuses to overwrite an existing note
    assert.ok(f.notes.createNote("Team Notes", "x").error);
    // create makes a new one (in a subfolder path)
    r = f.notes.createNote("Archive/Old", "archived");
    assert.equal(r.path, join("Archive", "Old.md"));
    assert.match(readFileSync(join(f.root, "Archive", "Old.md"), "utf8"), /archived/);
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("note writes refuse paths outside the vault", () => {
  const f = fixture();
  try {
    assert.ok(f.notes.createNote("../escape", "x").error);
    assert.ok(f.notes.appendToNote("/etc/hosts", "x").error);
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
