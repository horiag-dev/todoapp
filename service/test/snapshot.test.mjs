import { test } from "node:test";
import assert from "node:assert/strict";
import { parseVault } from "../src/parse.mjs";
import { migrate } from "../src/migrate.mjs";
import { assignIds } from "../src/model.mjs";
import { snapshot } from "../src/agent.mjs";

const model = (md) => assignIds(migrate(parseVault(md)));

test("board snapshot carries ids for Urgent, Top 5, AND Normal (so 'delete it' needs no search)", () => {
  const m = model(`# Todo List

### 🔴 Urgent

- [ ] ⭐ Ship the release

### 🔵 Normal

- [ ] Water the plants
- [ ] Call the dentist
`);
  const s = snapshot(m, { list: () => [] });
  const dentist = m.normal.find((i) => i.title === "Call the dentist");
  // The Normal item appears WITH its id, so the model can act on it directly.
  assert.match(s, new RegExp(`${dentist.id} — Call the dentist`));
  const urgent = m.urgent[0];
  assert.match(s, new RegExp(`${urgent.id}.*Ship the release`));
});

test("Normal is capped in the snapshot, with a pointer to list_items for the rest", () => {
  const lines = Array.from({ length: 55 }, (_, i) => `- [ ] Task ${i}`).join("\n");
  const m = model(`# Todo List\n\n### 🔵 Normal\n\n${lines}\n`);
  const s = snapshot(m, { list: () => [] });
  assert.match(s, /and 15 more \(use list_items "normal"\)/);
});
