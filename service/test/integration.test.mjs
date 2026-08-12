// End-to-end: create our own markdown vault file, load it, mutate it, save,
// and verify the changes round-trip through disk (add a todo, remove a todo,
// complete, mark Today) with atomic write + history.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Vault } from "../src/vault.mjs";
import { assignIds } from "../src/model.mjs";
import { applyAction } from "../src/ops.mjs";

const FIXTURE = `# Todo List

## 🎯 Goals

**Work**
- Ship the thing

### 🔴 Top 5 of the week

- [ ] Weekly priority

### 🔴 Urgent

- [ ] ⭐ Fix the build
- [ ] Review the PR

### 🔵 Normal

- [ ] Read the docs

### ✅ Completed

### 🗑️ Deleted
`;

function makeVault() {
  const dir = mkdtempSync(join(tmpdir(), "bigrocks-"));
  const doc = join(dir, "todo.md");
  writeFileSync(doc, FIXTURE, "utf8");
  return { vault: new Vault({ todoDocPath: doc }), dir, doc };
}

test("create md file → add a todo → persists to disk", () => {
  const { vault, dir, doc } = makeVault();
  try {
    const m = assignIds(vault.load());
    assert.equal(m.urgent.length, 2);
    applyAction(m, "add", { title: "Buy milk", bucket: "normal" });
    vault.save(m);
    const reloaded = assignIds(vault.load());
    assert.ok(reloaded.normal.find((i) => i.title === "Buy milk"), "present after reload");
    assert.match(readFileSync(doc, "utf8"), /- \[ \] Buy milk/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("remove a todo → moves to Deleted on disk, gone from its bucket", () => {
  const { vault, dir, doc } = makeVault();
  try {
    const m = assignIds(vault.load());
    applyAction(m, "delete", { id: m.normal.find((i) => i.title === "Read the docs").id });
    vault.save(m);
    const reloaded = assignIds(vault.load());
    assert.ok(!reloaded.normal.find((i) => i.title === "Read the docs"), "gone from Normal");
    assert.ok(reloaded.deleted.find((i) => i.title === "Read the docs"), "now in Deleted");
    assert.match(readFileSync(doc, "utf8"), /### 🗑️ Deleted[\s\S]*Read the docs/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("complete + mark Today round-trip through the file; history is written", () => {
  const { vault, dir, doc } = makeVault();
  try {
    const m = assignIds(vault.load());
    applyAction(m, "toggleToday", { id: m.urgent.find((i) => i.title === "Review the PR").id });
    applyAction(m, "complete", { id: m.normal.find((i) => i.title === "Read the docs").id });
    vault.save(m);

    const file = readFileSync(doc, "utf8");
    assert.match(file, /- \[ \] ⭐ Review the PR/, "Today = ⭐ on disk");
    assert.match(file, /### ✅ Completed[\s\S]*Read the docs/, "completed section");

    const reloaded = assignIds(vault.load());
    assert.equal(reloaded.urgent.find((i) => i.title === "Review the PR").starred, true);
    assert.ok(reloaded.completed.find((i) => i.title === "Read the docs"));

    // an atomic-write history snapshot + log entry exist
    assert.match(readFileSync(join(dir, ".bigrocks", "log.jsonl"), "utf8"), /"op":"write"/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("Goals notepad and frontmatter-free preamble survive a mutate+save", () => {
  const { vault, dir, doc } = makeVault();
  try {
    const m = assignIds(vault.load());
    applyAction(m, "add", { title: "Something new" });
    vault.save(m);
    const file = readFileSync(doc, "utf8");
    assert.match(file, /## 🎯 Goals\s+\*\*Work\*\*\s+- Ship the thing/, "goals preserved verbatim");
    assert.ok(file.startsWith("# Todo List"), "title preserved");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
