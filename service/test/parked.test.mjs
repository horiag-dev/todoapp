import { test } from "node:test";
import assert from "node:assert/strict";
import { parseVault } from "../src/parse.mjs";
import { migrate } from "../src/migrate.mjs";
import { serialize } from "../src/serialize.mjs";
import { assignIds } from "../src/model.mjs";
import { applyAction } from "../src/ops.mjs";

const roundtrip = (doc) => serialize(migrate(parseVault(doc)));
const load = (doc) => assignIds(migrate(parseVault(doc)));

const WITH_PARKED = `# Todo List

### 🔴 Top 5 of the week

### 🔴 Urgent

- [ ] Ship it

### 🔵 Normal

### 💤 Parked

- [ ] Someday idea
- [ ] Another parked thing

### ✅ Completed

### 🗑️ Deleted
`;

const NO_PARKED = `# Todo List

### 🔴 Top 5 of the week

### 🔴 Urgent

- [ ] X

### 🔵 Normal

### ✅ Completed

### 🗑️ Deleted
`;

test("a Parked section parses and round-trips byte-identically", () => {
  assert.equal(roundtrip(WITH_PARKED), WITH_PARKED);
  const m = migrate(parseVault(WITH_PARKED));
  assert.equal(m.parked.length, 2);
  assert.equal(m.parked[0].title, "Someday idea");
});

test("a file without a Parked section never gains one", () => {
  assert.equal(roundtrip(NO_PARKED), NO_PARKED);
  assert.doesNotMatch(roundtrip(NO_PARKED), /Parked/);
});

test("park hides an item; unpark brings it back to Normal", () => {
  const m = load(WITH_PARKED);
  const id = m.urgent[0].id;
  assert.match(applyAction(m, "park", { id }), /parked/);
  assert.equal(m.urgent.length, 0);
  const parked = m.parked.find((it) => it.title === "Ship it");
  assert.ok(parked, "moved to Parked");
  assert.match(applyAction(m, "unpark", { id: parked.id }), /un-parked/);
  assert.ok(m.normal.some((it) => it.title === "Ship it"), "back in Normal");
  assert.ok(!m.parked.some((it) => it.title === "Ship it"));
});

test("parking an empty file's item then unparking all removes the Parked section", () => {
  const m = load(NO_PARKED);
  applyAction(m, "park", { id: m.urgent[0].id });
  assert.match(serialize(m), /💤 Parked/); // section appears while occupied
  applyAction(m, "unpark", { id: m.parked[0].id });
  assert.doesNotMatch(serialize(m), /Parked/); // and vanishes when empty
});
