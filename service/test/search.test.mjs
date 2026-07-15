import { test } from "node:test";
import assert from "node:assert/strict";
import { searchModel, assignIds } from "../src/model.mjs";
import { migrate } from "../src/migrate.mjs";
import { parseVault } from "../src/parse.mjs";

const DOC = `# Todo List

## 🎯 Goals

**Health** #health
- Get back to running 3x a week

### 🔴 Top 5 of the week

- [ ] Finish the launch deck

## 📚 To Read

- https://example.com/running-guide

### 🔴 Urgent

- [ ] Book the venue

### 🔵 Normal

- [ ] Organize the garage

### ✅ Completed

- [x] Send the Q3 report

### 🗑️ Deleted
`;
const model = assignIds(migrate(parseVault(DOC)));

test("search covers items, completed, goals, and to-read", () => {
  assert.deepEqual(searchModel(model, ""), []); // empty query → no hits
  assert.deepEqual(searchModel(model, "   "), []);

  assert.ok(searchModel(model, "venue").some((h) => h.bucket === "urgent"));
  assert.ok(searchModel(model, "garage").some((h) => h.bucket === "normal"));
  assert.ok(searchModel(model, "deck").some((h) => h.bucket === "top5"));
  assert.ok(searchModel(model, "report").some((h) => h.bucket === "completed")); // finds already-done work

  const running = searchModel(model, "running");
  assert.ok(running.some((h) => h.bucket === "goals"), "matches the Goals notepad");
  assert.ok(running.some((h) => h.bucket === "toread"), "matches the To Read list");

  assert.equal(searchModel(model, "nonexistent-xyz").length, 0);
});

test("search is case-insensitive and item hits carry id + bucket", () => {
  const hits = searchModel(model, "VENUE");
  assert.equal(hits.length, 1);
  assert.equal(hits[0].bucket, "urgent");
  assert.ok(hits[0].id, "item hits include an id");
});
