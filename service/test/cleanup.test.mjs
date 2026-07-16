import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync, statSync, symlinkSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createCleanup } from "../src/cleanup.mjs";

// Is the filesystem under `dir` case-insensitive (macOS APFS default)? Some
// regression tests below only bite on such volumes; skip their FS-specific leg
// elsewhere while still asserting the operation is refused for SOME reason.
function caseInsensitive(dir) {
  const p = join(dir, "CaseProbe.md");
  writeFileSync(p, "x");
  try { return existsSync(join(dir, "caseprobe.md")); } finally { rmSync(p, { force: true }); }
}

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "bigrocks-cleanup-"));
  writeFileSync(join(root, "todo.md"), "# Todo\n");
  writeFileSync(join(root, "Assistant Memory.md"), "# Assistant Memory\n");
  writeFileSync(join(root, "Standup notes.md"), "# Standup\n\nWeekly sync notes.\n");
  writeFileSync(join(root, "Roadmap.md"), "# Roadmap\n\nLaunch in Q3.\n");
  writeFileSync(join(root, "Team Notes.md"), "See [[Roadmap]] for the plan.\n"); // links to Roadmap
  writeFileSync(join(root, "Untitled 7.md"), "   \n"); // empty
  writeFileSync(join(root, "Keeper.md"), "Important. #keep\n");
  writeFileSync(join(root, "Ideas.md"), "one\ntwo\n");
  writeFileSync(join(root, "Ideas (copy).md"), "one\ntwo\n"); // exact dup of Ideas
  mkdirSync(join(root, ".obsidian"));
  writeFileSync(join(root, ".obsidian", "config"), "x");
  const vault = {
    vaultPath: root,
    todoDocPath: join(root, "todo.md"),
    memoryPath: join(root, "Assistant Memory.md"),
    machineDir: join(root, ".bigrocks"),
  };
  return { root, vault, cleanup: createCleanup(vault) };
}
const cleanupAll = (root) => rmSync(root, { recursive: true, force: true });

test("overview: tree, empty flag, inbound links, protected list", () => {
  const f = fixture();
  try {
    const o = f.cleanup.overview();
    const roadmap = o.notes.find((n) => n.note === "Roadmap.md");
    const untitled = o.notes.find((n) => n.note === "Untitled 7.md");
    assert.equal(roadmap.inboundLinks, 1, "Roadmap is linked by Team Notes");
    assert.equal(untitled.empty, true, "whitespace-only note is empty");
    assert.ok(o.protected.includes("todo.md") && o.protected.includes("Assistant Memory.md"));
    assert.ok(!o.notes.some((n) => n.note === "todo.md" || n.note === "Assistant Memory.md"));
  } finally { cleanupAll(f.root); }
});

test("duplicates: exact content group and title-variant group", () => {
  const f = fixture();
  try {
    const d = f.cleanup.duplicates();
    assert.ok(d.exact.some((g) => g.includes("Ideas.md") && g.includes("Ideas (copy).md")));
  } finally { cleanupAll(f.root); }
});

test("stage/execute a move: file lands in a new folder, source gone", () => {
  const f = fixture();
  try {
    const { intent, error } = f.cleanup.stageMove({ path: "Standup notes.md", to_folder: "Meetings", reason: "meeting note" });
    assert.ok(!error && intent);
    assert.match(intent.label, /new folder/);
    const batch = f.cleanup.openBatch();
    const r = f.cleanup.execute(intent, batch);
    f.cleanup.closeBatch(batch);
    assert.equal(r.moved, true);
    assert.ok(existsSync(join(f.root, "Meetings", "Standup notes.md")));
    assert.ok(!existsSync(join(f.root, "Standup notes.md")));
  } finally { cleanupAll(f.root); }
});

test("precondition: a note changed after staging is SKIPPED, not forced", () => {
  const f = fixture();
  try {
    const { intent } = f.cleanup.stageMove({ path: "Standup notes.md", to_folder: "Meetings", reason: "x" });
    writeFileSync(join(f.root, "Standup notes.md"), "edited since staging\n"); // mutate on disk
    const batch = f.cleanup.openBatch();
    const r = f.cleanup.execute(intent, batch);
    assert.equal(r.skipped, true);
    assert.ok(existsSync(join(f.root, "Standup notes.md")), "source untouched");
    assert.ok(!existsSync(join(f.root, "Meetings", "Standup notes.md")), "not moved");
  } finally { cleanupAll(f.root); }
});

test("trash roundtrip: goes to .bigrocks/trash, undo restores it byte-identical", () => {
  const f = fixture();
  try {
    const before = readFileSync(join(f.root, "Untitled 7.md"));
    const { intent } = f.cleanup.stageTrash({ path: "Untitled 7.md", reason: "empty note" });
    const batch = f.cleanup.openBatch();
    const r = f.cleanup.execute(intent, batch);
    f.cleanup.closeBatch(batch);
    assert.equal(r.trashed, true);
    assert.ok(!existsSync(join(f.root, "Untitled 7.md")), "removed from the vault");
    assert.ok(existsSync(join(f.root, ".bigrocks", "trash", batch.ts, "Untitled 7.md")), "moved into recoverable trash");
    assert.ok(f.cleanup.hasBatches());
    const u = f.cleanup.undoLastBatch();
    assert.equal(u.done, true);
    assert.equal(u.restored, 1);
    assert.deepEqual(readFileSync(join(f.root, "Untitled 7.md")), before);
    assert.ok(!f.cleanup.hasBatches(), "manifest removed after full undo");
  } finally { cleanupAll(f.root); }
});

test("multi-op batch undo restores the whole vault", () => {
  const f = fixture();
  try {
    const snapshot = (name) => existsSync(join(f.root, name)) ? readFileSync(join(f.root, name), "utf8") : null;
    const roadmapBefore = snapshot("Roadmap.md");
    const m1 = f.cleanup.stageMove({ path: "Roadmap.md", to_folder: "Projects", reason: "a" }).intent;
    const t1 = f.cleanup.stageTrash({ path: "Untitled 7.md", reason: "empty" }).intent;
    const batch = f.cleanup.openBatch();
    f.cleanup.execute(m1, batch);
    f.cleanup.execute(t1, batch);
    f.cleanup.closeBatch(batch);
    assert.ok(existsSync(join(f.root, "Projects", "Roadmap.md")));
    assert.ok(!existsSync(join(f.root, "Untitled 7.md")));
    const u = f.cleanup.undoLastBatch();
    assert.equal(u.done, true);
    assert.ok(existsSync(join(f.root, "Roadmap.md")) && !existsSync(join(f.root, "Projects", "Roadmap.md")));
    assert.ok(existsSync(join(f.root, "Untitled 7.md")));
    assert.equal(snapshot("Roadmap.md"), roadmapBefore);
  } finally { cleanupAll(f.root); }
});

test("#keep notes are never trashed", () => {
  const f = fixture();
  try {
    const r = f.cleanup.stageTrash({ path: "Keeper.md", reason: "cleanup" });
    assert.ok(r.error && /#keep/.test(r.error));
    assert.ok(existsSync(join(f.root, "Keeper.md")));
  } finally { cleanupAll(f.root); }
});

test("linked notes refuse trash unless force_linked_ok", () => {
  const f = fixture();
  try {
    const refused = f.cleanup.stageTrash({ path: "Roadmap.md", reason: "old" });
    assert.ok(refused.error && /link/.test(refused.error));
    const forced = f.cleanup.stageTrash({ path: "Roadmap.md", reason: "old", force_linked_ok: true });
    assert.ok(forced.intent && forced.intent.forced === true);
    assert.match(forced.intent.label, /⚠/);
  } finally { cleanupAll(f.root); }
});

test("path safety: escapes, protected files, and dotfolders are refused at stage", () => {
  const f = fixture();
  try {
    assert.ok(f.cleanup.stageMove({ path: "../escape.md", to_folder: "x", reason: "" }).error);
    // A leading "./" is trimmed, so a plain subfolder is fine…
    assert.ok(!f.cleanup.stageMove({ path: "Standup notes.md", to_folder: "./Meetings", reason: "" }).error);
    // …but traversals that escape the vault, and dot-prefixed system folders, are refused.
    assert.ok(f.cleanup.stageMove({ path: "Standup notes.md", to_folder: "../out", reason: "" }).error);
    assert.ok(f.cleanup.stageMove({ path: "Standup notes.md", to_folder: "ok/../../../escape", reason: "" }).error);
    assert.ok(f.cleanup.stageMove({ path: "Standup notes.md", to_folder: ".obsidian", reason: "" }).error);
    assert.ok(f.cleanup.stageMove({ path: "Standup notes.md", to_folder: ".git", reason: "" }).error);
    assert.ok(f.cleanup.stageTrash({ path: "todo.md", reason: "" }).error, "todo doc protected");
    assert.ok(f.cleanup.stageTrash({ path: "Assistant Memory.md", reason: "" }).error, "memory protected");
    assert.ok(f.cleanup.stageTrash({ path: "/etc/hosts", reason: "" }).error);
  } finally { cleanupAll(f.root); }
});

test("move refuses when the destination already exists (no overwrite)", () => {
  const f = fixture();
  try {
    mkdirSync(join(f.root, "Meetings"));
    writeFileSync(join(f.root, "Meetings", "Standup notes.md"), "different\n");
    const r = f.cleanup.stageMove({ path: "Standup notes.md", to_folder: "Meetings", reason: "" });
    assert.ok(r.error && /already exists/.test(r.error));
  } finally { cleanupAll(f.root); }
});

test("move refuses when other notes link by folder-path (link integrity, MVP)", () => {
  const f = fixture();
  try {
    // Team Notes links [[Roadmap]] (bare) — fine to move. Add a path-style referrer.
    writeFileSync(join(f.root, "Deep.md"), "ref [[folder/Roadmap]] here\n");
    // Put Roadmap under folder/ so the path-style link actually targets it.
    mkdirSync(join(f.root, "folder"));
    writeFileSync(join(f.root, "folder", "Roadmap.md"), "# R\n");
    rmSync(join(f.root, "Roadmap.md"));
    const cl = createCleanup(f.vault);
    const r = cl.stageMove({ path: "folder/Roadmap.md", to_folder: "Projects", reason: "" });
    assert.ok(r.error && /folder path/.test(r.error));
  } finally { cleanupAll(f.root); }
});

test("SECURITY: the todo doc / memory note can't be trashed or moved via an alternate-case path", () => {
  const f = fixture();
  try {
    // On case-insensitive volumes "Todo" resolves to the real todo.md; the
    // protected-file check must catch it regardless of casing (Finding 1).
    assert.ok(f.cleanup.stageTrash({ path: "Todo.md", reason: "x" }).error, "Todo.md refused");
    assert.ok(f.cleanup.stageTrash({ path: "todo", reason: "x" }).error, "todo refused");
    assert.ok(f.cleanup.stageMove({ path: "TODO.md", to_folder: "Archive", reason: "x" }).error, "TODO.md move refused");
    assert.ok(f.cleanup.stageMove({ path: "Assistant memory.md", to_folder: "Archive", reason: "x" }).error, "memory refused");
    if (caseInsensitive(f.root)) {
      assert.ok(existsSync(join(f.root, "todo.md")), "todo.md untouched");
      assert.ok(existsSync(join(f.root, "Assistant Memory.md")), "memory untouched");
    }
  } finally { cleanupAll(f.root); }
});

test("SECURITY: notes can't be moved into the reserved attachments folder by case (Finding 2)", () => {
  const f = fixture();
  try {
    assert.ok(f.cleanup.stageMove({ path: "Standup notes.md", to_folder: "Attachments", reason: "" }).error);
    assert.ok(f.cleanup.stageMove({ path: "Standup notes.md", to_folder: "NODE_MODULES", reason: "" }).error);
  } finally { cleanupAll(f.root); }
});

test("SECURITY: a move through a symlinked in-vault folder can't escape the vault (Finding 3)", () => {
  const f = fixture();
  const outside = mkdtempSync(join(tmpdir(), "bigrocks-outside-"));
  try {
    symlinkSync(outside, join(f.root, "Escape")); // in-vault folder pointing out
    const cl = createCleanup(f.vault);
    const r = cl.stageMove({ path: "Standup notes.md", to_folder: "Escape", reason: "" });
    assert.ok(r.error, "move into a symlinked-out folder is refused");
    assert.ok(existsSync(join(f.root, "Standup notes.md")), "source untouched");
    assert.ok(!existsSync(join(outside, "Standup notes.md")), "nothing written outside the vault");
  } finally { cleanupAll(f.root); cleanupAll(outside); }
});

test("recoverability: the undo manifest is written incrementally, per op (Finding 5)", () => {
  const f = fixture();
  try {
    const { intent } = f.cleanup.stageTrash({ path: "Untitled 7.md", reason: "empty" });
    const batch = f.cleanup.openBatch();
    f.cleanup.execute(intent, batch); // NOTE: no closeBatch() yet
    const dir = join(f.root, ".bigrocks", "cleanup");
    assert.ok(existsSync(dir) && readdirSync(dir).some((x) => x.endsWith(".json")),
      "a crash right after the op would still leave an undoable manifest");
  } finally { cleanupAll(f.root); }
});

test("no hard-delete of user notes: source contains no unlinkSync", () => {
  const src = readFileSync(new URL("../src/cleanup.mjs", import.meta.url), "utf8");
  assert.ok(!src.includes("unlinkSync"), "cleanup must never unlinkSync a user note");
});
