import { test } from "node:test";
import assert from "node:assert/strict";
import { parseVault } from "../src/parse.mjs";
import { migrate, hasHack, cleanHack } from "../src/migrate.mjs";

test("hasHack matches the all-caps hack, not ordinary prose", () => {
  assert.equal(hasHack("TODAY - x"), true);
  assert.equal(hasHack("TODAy - x"), true);
  assert.equal(hasHack("Sunil - TODAY REPLY"), true);
  assert.equal(hasHack("do this today please"), false); // lowercase prose
  assert.equal(hasHack("Today standup notes"), false); // mixed case, not the hack
  assert.equal(hasHack("has #today tag"), true);
});

test("cleanHack strips the marker and tidies punctuation", () => {
  assert.equal(cleanHack("TODAY - re-create the DX AI PM meeting"), "re-create the DX AI PM meeting");
  assert.equal(cleanHack("Skills coverage - TODAY - talk to Rachel"), "Skills coverage - talk to Rachel");
  assert.equal(cleanHack("Sunil - TODAY REPLY"), "Sunil - REPLY");
  assert.equal(cleanHack("TODAy - create extensibility slide"), "create extensibility slide");
  assert.equal(cleanHack("TODAY - Sunil asks"), "Sunil asks");
});

test("migrate: Today→Urgent(+star)/Normal, This Week→Normal", () => {
  const doc = [
    "# Todo List",
    "",
    "### ☀️ Today",
    "",
    "- [ ] TODAY - alpha",
    "- [ ] normal today item",
    "- [ ] TODAy - beta",
    "",
    "### 🔴 Urgent",
    "",
    "- [ ] existing urgent",
    "",
    "### 🟠 This Week",
    "",
    "- [ ] weekly item",
    "",
    "### 🔵 Normal",
    "",
    "- [ ] plain normal",
  ].join("\n");

  const m = migrate(parseVault(doc));

  // Urgent = 2 starred (from Today hacks, cleaned) then existing urgent.
  assert.deepEqual(
    m.urgent.map((i) => `${i.starred ? "*" : ""}${i.title}`),
    ["*alpha", "*beta", "existing urgent"],
  );
  assert.equal(m.urgent.filter((i) => i.starred).length, 2);

  // Normal = existing normal + Today leftover + This Week.
  assert.deepEqual(m.normal.map((i) => i.title), ["plain normal", "normal today item", "weekly item"]);

  // No Today/This Week survive as buckets.
  assert.ok(!("today" in m) && !("thisweek" in m));
});
