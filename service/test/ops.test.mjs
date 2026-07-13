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

test("serialize reflects mutations (Today = ⭐ on disk)", () => {
  const m = model(BASE);
  applyAction(m, "add", { title: "New task #proj", today: true });
  assert.match(serialize(m), /- \[ \] ⭐ New task #proj/);
});
