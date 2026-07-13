import { test } from "node:test";
import assert from "node:assert/strict";
import { parseVault } from "../src/parse.mjs";
import { migrate } from "../src/migrate.mjs";
import { assignIds } from "../src/model.mjs";
import { applyAction } from "../src/ops.mjs";
import { serialize } from "../src/serialize.mjs";

const model = (md) => assignIds(migrate(parseVault(md)));
const idOf = (m, b, title) => m[b].find((i) => i.title === title).id;

const BASE = `# Todo List

### 🔴 Urgent

- [ ] ⭐ Fix the build
- [ ] Review the PR

### 🔵 Normal

- [ ] Read the docs
`;

test("add: lands in the bucket; a Today item sits above non-Today urgent items", () => {
  const m = model(BASE);
  applyAction(m, "add", { title: "Buy milk", bucket: "normal" });
  assert.equal(m.normal.at(-1).title, "Buy milk");

  applyAction(m, "add", { title: "Call now", today: true });
  const call = m.urgent.find((i) => i.title === "Call now");
  assert.equal(call.starred, true);
  // it's within the Today (starred) group — before the first non-Today urgent item
  const callIdx = m.urgent.findIndex((i) => i.title === "Call now");
  const firstPlain = m.urgent.findIndex((i) => !i.starred);
  assert.ok(callIdx < firstPlain, "Today item floats above non-Today urgent items");
});

test("complete: moves the item into Completed", () => {
  const m = model(BASE);
  applyAction(m, "complete", { id: idOf(m, "urgent", "Review the PR") });
  assert.ok(!m.urgent.find((i) => i.title === "Review the PR"));
  assert.equal(m.completed.at(-1).title, "Review the PR");
  assert.equal(m.completed.at(-1).checked, true);
});

test("delete: moves the item into Deleted (recoverable)", () => {
  const m = model(BASE);
  applyAction(m, "delete", { id: idOf(m, "normal", "Read the docs") });
  assert.ok(!m.normal.find((i) => i.title === "Read the docs"));
  assert.equal(m.deleted.at(-1).title, "Read the docs");
});

test("toggleToday: sets then clears the Today marker", () => {
  const m = model(BASE);
  const id = idOf(m, "urgent", "Review the PR");
  applyAction(m, "toggleToday", { id });
  assert.equal(m.urgent.find((i) => i.id === id).starred, true);
  applyAction(m, "toggleToday", { id });
  assert.equal(m.urgent.find((i) => i.id === id).starred, false);
});

test("setPriority: moves an item between Normal and Urgent", () => {
  const m = model(BASE);
  applyAction(m, "setPriority", { id: idOf(m, "normal", "Read the docs"), bucket: "urgent" });
  assert.ok(m.urgent.find((i) => i.title === "Read the docs"));
  assert.ok(!m.normal.find((i) => i.title === "Read the docs"));
});

test("reorder: swaps within the same Today group, never across it", () => {
  const m = model(`# Todo List

### 🔴 Urgent

- [ ] ⭐ A
- [ ] ⭐ B
- [ ] C
- [ ] D
`);
  applyAction(m, "reorder", { id: idOf(m, "urgent", "B"), dir: "up" });
  assert.deepEqual(m.urgent.map((i) => i.title), ["B", "A", "C", "D"]);
  const before = m.urgent.map((i) => i.title);
  applyAction(m, "reorder", { id: idOf(m, "urgent", "A"), dir: "down" }); // would cross into non-Today → no-op
  assert.deepEqual(m.urgent.map((i) => i.title), before);
});

test("editTitle: renames an item", () => {
  const m = model(BASE);
  applyAction(m, "editTitle", { id: idOf(m, "urgent", "Review the PR"), title: "Review the PR carefully" });
  assert.ok(m.urgent.find((i) => i.title === "Review the PR carefully"));
});

test("moveToGoals: appends a bullet under a subsection and removes from the bucket", () => {
  const m = model(`# Todo List

## 🎯 Goals

**Work**
- existing

### 🔴 Urgent

- [ ] think about the charter
`);
  const id = m.urgent[0].id;
  applyAction(m, "moveToGoals", { id, subsection: "Work" });
  assert.ok(!m.urgent.find((i) => i.id === id));
  assert.ok(m.goals.rawLines.includes("- think about the charter"));
});

test("serialize reflects mutations (Today = ⭐ on disk)", () => {
  const m = model(BASE);
  applyAction(m, "add", { title: "New task #proj", today: true });
  assert.match(serialize(m), /- \[ \] ⭐ New task #proj/);
});

test("restore and permanent delete manage the recoverable lifecycle", () => {
  const m = model(BASE);
  const id = idOf(m, "normal", "Read the docs");
  applyAction(m, "delete", { id });
  const deletedId = m.deleted[0].id;
  applyAction(m, "restore", { id: deletedId });
  assert.equal(m.normal.at(-1).title, "Read the docs");
  assert.equal(m.normal.at(-1).checked, false);
  applyAction(m, "delete", { id: m.normal.at(-1).id });
  applyAction(m, "permanentDelete", { id: m.deleted[0].id });
  assert.equal(m.deleted.length, 0);
});

test("Top 5 can be added, reordered, and cleared", () => {
  const m = model(BASE);
  applyAction(m, "addTop5", { title: "First" });
  applyAction(m, "addTop5", { title: "Second" });
  applyAction(m, "reorderTop5", { id: m.top5[1].id, dir: "up" });
  assert.deepEqual(m.top5.map((i) => i.title), ["Second", "First"]);
  applyAction(m, "clearTop5");
  assert.equal(m.top5.length, 0);
});

test("drag ordering persists within Top 5, Urgent, and Normal", () => {
  const m = model(`# Todo List

### 🔴 Top 5 of the week
- [ ] T1
- [ ] T2

### 🔴 Urgent
- [ ] U1
- [ ] U2

### 🔵 Normal
- [ ] N1
- [ ] N2
- [ ] N3
`);
  applyAction(m, "reorderTo", { bucket: "top5", id: idOf(m, "top5", "T2"), targetId: idOf(m, "top5", "T1"), position: "before" });
  applyAction(m, "reorderTo", { bucket: "urgent", id: idOf(m, "urgent", "U1"), targetId: idOf(m, "urgent", "U2"), position: "after" });
  applyAction(m, "reorderTo", { bucket: "normal", id: idOf(m, "normal", "N3"), targetId: idOf(m, "normal", "N1"), position: "after" });
  assert.deepEqual(m.top5.map((i) => i.title), ["T2", "T1"]);
  assert.deepEqual(m.urgent.map((i) => i.title), ["U2", "U1"]);
  assert.deepEqual(m.normal.map((i) => i.title), ["N1", "N3", "N2"]);
  assert.match(serialize(m), /### 🔵 Normal[\s\S]*N1[\s\S]*N3[\s\S]*N2/);
});

test("dragging across Today, Urgent, and Normal changes destination state", () => {
  const m = model(`# Todo List

### 🔴 Urgent
- [ ] ⭐ Today item
- [ ] Plain item

### 🔵 Normal
- [ ] Normal item
`);
  applyAction(m, "reorderTo", {
    bucket: "today",
    id: idOf(m, "urgent", "Plain item"),
    targetId: idOf(m, "urgent", "Today item"),
    position: "after",
  });
  assert.deepEqual(m.urgent.map((i) => [i.title, i.starred]), [
    ["Today item", true],
    ["Plain item", true],
  ]);

  applyAction(m, "reorderTo", {
    bucket: "normal",
    id: idOf(m, "urgent", "Today item"),
    targetId: idOf(m, "normal", "Normal item"),
    position: "before",
  });
  assert.deepEqual(m.normal.map((i) => [i.title, i.starred]), [
    ["Today item", false],
    ["Normal item", false],
  ]);

  applyAction(m, "reorderTo", {
    bucket: "urgent",
    id: idOf(m, "normal", "Normal item"),
    targetId: null,
    position: "after",
  });
  assert.deepEqual(m.urgent.map((i) => [i.title, i.starred]), [
    ["Plain item", true],
    ["Normal item", false],
  ]);
});

test("To Read direct operations preserve section syntax", () => {
  const m = model(BASE);
  applyAction(m, "addToRead", { text: "https://example.com" });
  assert.deepEqual(m.toread.rawLines, ["- https://example.com"]);
  applyAction(m, "removeFromRead", { index: 0 });
  assert.deepEqual(m.toread.rawLines, []);
});

test("renameTag changes matching tags across active and Top 5 items", () => {
  const m = model(BASE);
  applyAction(m, "addTop5", { title: "Plan #old" });
  applyAction(m, "add", { title: "Build #old", bucket: "normal" });
  applyAction(m, "renameTag", { from: "old", to: "new" });
  assert.equal(m.top5[0].title, "Plan #new");
  assert.equal(m.normal.at(-1).title, "Build #new");
});
