// Splitting a jammed row into real todos. A row that bundles several tasks can
// never be ticked off, so it sits in Urgent forever — 16 of 64 active items in
// the real file are shaped this way.
import test from "node:test";
import assert from "node:assert/strict";
import { parseVault } from "../src/parse.mjs";
import { migrate } from "../src/migrate.mjs";
import { serialize } from "../src/serialize.mjs";
import { assignIds, countMusts } from "../src/model.mjs";
import { applyAction, splitItem } from "../src/ops.mjs";

const doc = (urgent) => [
  "# Todo List", "", "## 🎯 Goals", "", "### 🔴 Top 5 of the week", "", "## 📚 To Read", "",
  "### 🔴 Urgent", "", ...urgent, "",
  "### 🔵 Normal", "", "### ✅ Completed", "", "### 🗑️ Deleted",
].join("\n");
const load = (urgent) => assignIds(migrate(parseVault(doc(urgent))));
const shape = (arr) => arr.map((i) => (i.blocked ? "↳" : i.must ? "!" : i.starred ? "*" : "-") + i.title);
const first = (m) => m.urgent[0].id;

test("splits one row into several, in place", () => {
  const m = load(["- [ ] Alpha", "- [ ] Beta and Gamma", "- [ ] Delta"]);
  const id = m.urgent[1].id;
  applyAction(m, "split", { id, parts: ["Beta", "Gamma"] });
  assert.deepEqual(shape(m.urgent), ["-Alpha", "-Beta", "-Gamma", "-Delta"]);
});

test("sequential=true makes the parts a queue", () => {
  const m = load(["- [ ] Book venue and send invites"]);
  applyAction(m, "split", { id: first(m), parts: ["Book the venue", "Send invites"], sequential: true });
  assert.deepEqual(shape(m.urgent), ["-Book the venue", "↳Send invites"]);
});

test("without sequential the parts are independent", () => {
  const m = load(["- [ ] Read the minutes, also Pat's deck"]);
  applyAction(m, "split", { id: first(m), parts: ["Read the minutes", "Read Pat's deck"] });
  assert.equal(m.urgent.every((i) => !i.blocked), true);
});

// --- tags: the file's main organizing axis, so a split must not lose them ------

test("tags dropped by every part are restored to all of them", () => {
  const m = load(["- [ ] Read Anoop's minutes, also Pat's deck #buildvsbuy"]);
  applyAction(m, "split", { id: first(m), parts: ["Read Anoop's minutes", "Read Pat's deck"] });
  assert.deepEqual(m.urgent.map((i) => i.title), [
    "Read Anoop's minutes #buildvsbuy",
    "Read Pat's deck #buildvsbuy",
  ]);
});

test("tags the caller distributed deliberately are left alone", () => {
  // "Talk to Rachel and Sergey about charters #charters #team #rachel #sergey"
  const m = load(["- [ ] Talk to Rachel and Sergey about charters #charters #team #rachel #sergey"]);
  applyAction(m, "split", {
    id: first(m),
    parts: ["Talk to Rachel about charters #charters #rachel", "Talk to Sergey about charters #team #sergey"],
  });
  assert.deepEqual(m.urgent.map((i) => i.title), [
    "Talk to Rachel about charters #charters #rachel",
    "Talk to Sergey about charters #team #sergey",
  ]);
});

test("a partially-dropped tag set only restores what actually vanished", () => {
  const m = load(["- [ ] A and B #keep #lost"]);
  applyAction(m, "split", { id: first(m), parts: ["A #keep", "B"] });
  assert.deepEqual(m.urgent.map((i) => i.title), ["A #keep #lost", "B #lost"]);
});

// --- the ladder is preserved, and the Must cap can't be laundered ------------

test("only the head inherits Today", () => {
  const m = load(["- [ ] ⭐ Draft and send the update"]);
  applyAction(m, "split", { id: first(m), parts: ["Draft the update", "Send the update"] });
  assert.deepEqual(shape(m.urgent), ["*Draft the update", "-Send the update"]);
});

test("splitting a Must yields exactly one Must — the cap can't be gamed", () => {
  const m = load(["- [ ] ‼️ A", "- [ ] ‼️ B", "- [ ] ‼️ Prep the interview and read the deck"]);
  assert.equal(countMusts(m), 3);
  applyAction(m, "split", { id: m.urgent[2].id, parts: ["Prep the interview", "Read the deck"] });
  assert.equal(countMusts(m), 3, "still 3, not 4");
});

test("a sequential split of a Must keeps the head committed and queues the rest", () => {
  const m = load(["- [ ] ‼️ Book venue then send invites"]);
  applyAction(m, "split", { id: first(m), parts: ["Book the venue", "Send invites"], sequential: true });
  assert.deepEqual(shape(m.urgent), ["!Book the venue", "↳Send invites"]);
});

// --- guards ------------------------------------------------------------------

test("refuses fewer than two parts, or more than eight", () => {
  const m = load(["- [ ] One thing"]);
  assert.throws(() => applyAction(m, "split", { id: first(m), parts: ["Just this"] }), /at least two/);
  assert.throws(() => applyAction(m, "split", { id: first(m), parts: Array(9).fill("x") }), /at most 8/);
});

test("blank and whitespace-only parts are discarded before the count check", () => {
  const m = load(["- [ ] A and B"]);
  assert.throws(() => applyAction(m, "split", { id: first(m), parts: ["A", "   ", ""] }), /at least two/);
});

test("refuses to split something that isn't an active todo", () => {
  const m = load(["- [ ] Done thing"]);
  applyAction(m, "complete", { id: first(m) });
  assert.throws(() => splitItem(m, m.completed[0].id, ["A", "B"]), /only Urgent, Normal and Top 5/);
});

// --- the file stays clean ----------------------------------------------------

test("the split round-trips through markdown", () => {
  const m = load(["- [ ] ⭐ Set up time w/ KT and review with Ilya #governance"]);
  applyAction(m, "split", {
    id: first(m),
    parts: ["Set up time w/ KT", "Review with Ilya"],
    sequential: true,
  });
  const out = serialize(m);
  assert.match(out, /- \[ \] ⭐ Set up time w\/ KT #governance/);
  assert.match(out, /- \[ \] ↳ Review with Ilya #governance/);
  // and re-parsing gives the same model back
  assert.equal(serialize(migrate(parseVault(out))), out);
});

test("splitting a Normal item keeps it in Normal", () => {
  const m = assignIds(migrate(parseVault([
    "# Todo List", "", "### 🔴 Urgent", "", "### 🔵 Normal", "",
    "- [ ] Rubin + Coworker — create dashboards #strategy", "",
    "### ✅ Completed", "", "### 🗑️ Deleted",
  ].join("\n"))));
  applyAction(m, "split", { id: m.normal[0].id, parts: ["Rubin dashboards", "Coworker dashboards"] });
  assert.equal(m.normal.length, 2);
  assert.equal(m.urgent.length, 0);
});
