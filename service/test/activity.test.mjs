import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createNotes } from "../src/notes.mjs";
import { createActivity, logLine } from "../src/activity.mjs";

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "bigrocks-activity-"));
  writeFileSync(join(root, "todo.md"), "# Todo\n");
  writeFileSync(join(root, "Assistant Memory.md"), "# Assistant Memory\n");
  // A note that already opted in (has a ## Log section)
  writeFileSync(join(root, "Proactive Insights.md"), "# Proactive Insights\n\nThe project.\n\n## Log\n\n- 2026-07-01 ✓ kickoff\n");
  // A note with no ## Log yet
  writeFileSync(join(root, "Sergey.md"), "# Sergey\n\nOwns proactive insights.\n");
  const vault = { vaultPath: root, todoDocPath: join(root, "todo.md"), memoryPath: join(root, "Assistant Memory.md"), machineDir: join(root, ".bigrocks") };
  return { root, vault, notes: createNotes(vault), activity: createActivity(vault) };
}
const done = (root) => rmSync(root, { recursive: true, force: true });

test("logLine: dated, ✓, strips the self-link but keeps cross-links", () => {
  const line = logLine("Align with Sergey on proactive insights [[Sergey]] [[Proactive Insights]]", "Sergey", "2026-07-16");
  assert.equal(line, "- 2026-07-16 ✓ Align with Sergey on proactive insights [[Proactive Insights]]");
});

test("appendToLog: appends into an existing ## Log, refuses (noLog) when absent or missing", () => {
  const f = fixture();
  try {
    const r = f.notes.appendToLog("Proactive Insights", "- 2026-07-16 ✓ did a thing");
    assert.equal(r.path, "Proactive Insights.md");
    const txt = readFileSync(join(f.root, "Proactive Insights.md"), "utf8");
    assert.match(txt, /kickoff[\s\S]*did a thing/, "appended newest-last within the section");
    assert.ok(f.notes.appendToLog("Sergey", "- x").noLog, "no ## Log → noLog");
    assert.ok(f.notes.appendToLog("Nonexistent Person", "- x").noLog, "missing note → noLog");
  } finally { done(f.root); }
});

test("ensureLog: adds a ## Log to an existing note, and creates a new note with one", () => {
  const f = fixture();
  try {
    let r = f.notes.ensureLog("Sergey", "- 2026-07-16 ✓ first entry");
    assert.equal(r.created, false);
    const sergey = readFileSync(join(f.root, "Sergey.md"), "utf8");
    assert.match(sergey, /Owns proactive insights[\s\S]*## Log[\s\S]*first entry/);

    r = f.notes.ensureLog("Krystina", "- 2026-07-16 ✓ new person");
    assert.equal(r.created, true);
    const k = readFileSync(join(f.root, "Krystina.md"), "utf8");
    assert.match(k, /# Krystina[\s\S]*## Log[\s\S]*new person/);
  } finally { done(f.root); }
});

test("logCompletion: logs to opted-in notes, suggests the rest", () => {
  const f = fixture();
  try {
    const r = f.activity.logCompletion("Align with Sergey on proactive insights [[Sergey]] [[Proactive Insights]]");
    assert.deepEqual(r.logged.map((l) => l.note), ["Proactive Insights"], "the note with ## Log is written");
    assert.deepEqual(r.suggest.map((s) => s.note), ["Sergey"], "the note without ## Log is suggested");
    // The written line stripped its own self-link ([[Proactive Insights]]) but kept the cross-link
    assert.match(readFileSync(join(f.root, "Proactive Insights.md"), "utf8"), /✓ Align with Sergey on proactive insights \[\[Sergey\]\]/);
    // Nothing written to Sergey yet
    assert.ok(!/## Log/.test(readFileSync(join(f.root, "Sergey.md"), "utf8")));
  } finally { done(f.root); }
});

test("enable + undo: start a log, then reverse the append", () => {
  const f = fixture();
  try {
    const line = "- 2026-07-16 ✓ Align with Sergey";
    const en = f.activity.enable([{ note: "Sergey", line }]);
    assert.equal(en.logged.length, 1);
    assert.match(readFileSync(join(f.root, "Sergey.md"), "utf8"), /## Log[\s\S]*Align with Sergey/);
    const u = f.activity.undo(en.undo);
    assert.equal(u.removed, 1);
    assert.ok(!/Align with Sergey/.test(readFileSync(join(f.root, "Sergey.md"), "utf8")), "line removed on undo");
    assert.match(readFileSync(join(f.root, "Sergey.md"), "utf8"), /## Log/, "the empty section stays");
  } finally { done(f.root); }
});

test("a completed todo with no links logs nothing", () => {
  const f = fixture();
  try {
    const r = f.activity.logCompletion("Just a plain todo, no links");
    assert.deepEqual(r.logged, []);
    assert.deepEqual(r.suggest, []);
  } finally { done(f.root); }
});
