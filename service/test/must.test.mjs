// The Must tier — a hard commitment layered on Today, capped at 3.
// Ladder: Urgent (could) → Today (intends) → Must (committed).
import test from "node:test";
import assert from "node:assert/strict";
import { parseVault } from "../src/parse.mjs";
import { migrate } from "../src/migrate.mjs";
import { serialize } from "../src/serialize.mjs";
import { assignIds, reflowUrgent, countMusts, MUST_CAP } from "../src/model.mjs";
import { applyAction } from "../src/ops.mjs";

const doc = (urgentLines) => [
  "# Todo List",
  "",
  "## 🎯 Goals",
  "",
  "### 🔴 Top 5 of the week",
  "",
  "### 🔴 Urgent",
  "",
  ...urgentLines,
  "",
  "### 🔵 Normal",
  "",
  "- [ ] Someday thing",
  "",
  "### ✅ Completed",
  "",
  "### 🗑️ Deleted",
].join("\n");

const load = (lines) => assignIds(migrate(parseVault(doc(lines))));
const titles = (m) => m.urgent.map((i) => `${i.must ? "!" : i.starred ? "*" : "-"}${i.title}`);

// --- file format -------------------------------------------------------------

test("‼️ parses as Must and implies Today", () => {
  const m = load(["- [ ] ‼️ Ship the deck", "- [ ] ⭐ Call Raj", "- [ ] Read the spec"]);
  assert.deepEqual(m.urgent.map((i) => [i.title, i.must, i.starred]), [
    ["Ship the deck", true, true],
    ["Call Raj", false, true],
    ["Read the spec", false, false],
  ]);
});

test("a Must serializes with ‼️ only — never doubled up with the star", () => {
  const m = load(["- [ ] ‼️ Ship the deck"]);
  assert.match(serialize(m), /- \[ \] ‼️ Ship the deck/);
  assert.doesNotMatch(serialize(m), /⭐/);
});

test("a hand-typed ⭐+‼️ in either order round-trips to one marker", () => {
  for (const line of ["- [ ] ⭐ ‼️ Ship it", "- [ ] ‼️ ⭐ Ship it"]) {
    const m = load([line]);
    assert.equal(m.urgent[0].title, "Ship it", line);
    assert.equal(m.urgent[0].must, true, line);
    assert.match(serialize(m), /- \[ \] ‼️ Ship it/);
  }
});

test("titles stay verbatim through the Must marker (wikilinks + tags)", () => {
  const m = load(["- [ ] ‼️ Reply to [[Investor Update]] #fundraising"]);
  assert.equal(m.urgent[0].title, "Reply to [[Investor Update]] #fundraising");
});

test("a file with Musts round-trips byte-identically", () => {
  const src = doc(["- [ ] ‼️ Ship the deck", "- [ ] ⭐ Call Raj", "- [ ] Read the spec"]) + "\n";
  assert.equal(serialize(migrate(parseVault(src))), src);
});

// --- ordering ----------------------------------------------------------------

test("Must floats above Today, which floats above the rest", () => {
  const m = load(["- [ ] Read the spec", "- [ ] ⭐ Call Raj", "- [ ] ‼️ Ship the deck"]);
  reflowUrgent(m);
  assert.deepEqual(titles(m), ["!Ship the deck", "*Call Raj", "-Read the spec"]);
});

test("order within each rank is preserved", () => {
  const m = load(["- [ ] ‼️ A", "- [ ] ‼️ B", "- [ ] ⭐ C", "- [ ] ⭐ D", "- [ ] E"]);
  reflowUrgent(m);
  assert.deepEqual(titles(m), ["!A", "!B", "*C", "*D", "-E"]);
});

// --- the cap -----------------------------------------------------------------

test(`Must is capped at ${MUST_CAP} — the ${MUST_CAP + 1}th is refused, naming the current ones`, () => {
  const m = load(["- [ ] ‼️ A", "- [ ] ‼️ B", "- [ ] ‼️ C", "- [ ] ⭐ D"]);
  const d = m.urgent.find((i) => i.title === "D");
  assert.throws(() => applyAction(m, "toggleMust", { id: d.id }), /capped at 3.*A.*B.*C/s);
  // …and nothing changed
  assert.equal(countMusts(m), MUST_CAP);
  assert.equal(!!d.must, false);
});

test("clearing one Must makes room for another", () => {
  const m = load(["- [ ] ‼️ A", "- [ ] ‼️ B", "- [ ] ‼️ C", "- [ ] ⭐ D"]);
  const a = m.urgent.find((i) => i.title === "A");
  const d = m.urgent.find((i) => i.title === "D");
  applyAction(m, "toggleMust", { id: a.id });
  assert.equal(a.must, false);
  assert.equal(a.starred, true, "demoting a Must leaves it as Today, not off the list");
  applyAction(m, "toggleMust", { id: d.id });
  assert.equal(d.must, true);
  assert.equal(countMusts(m), MUST_CAP);
});

// --- promotion / demotion ----------------------------------------------------

test("promoting from Normal pulls the item into Urgent as Must + Today", () => {
  const m = load(["- [ ] ⭐ Call Raj"]);
  const n = m.normal[0];
  applyAction(m, "toggleMust", { id: n.id });
  assert.equal(m.normal.length, 0);
  assert.equal(m.urgent[0].title, "Someday thing");
  assert.equal(m.urgent[0].must, true);
  assert.equal(m.urgent[0].starred, true);
});

test("clearing Today on a Must clears the commitment too", () => {
  const m = load(["- [ ] ‼️ Ship the deck"]);
  const it = m.urgent[0];
  applyAction(m, "toggleToday", { id: it.id });
  assert.equal(it.starred, false);
  assert.equal(it.must, false, "an intention you dropped can't still be a commitment");
});

test("moving a Must to Normal, parking, completing or deleting clears it", () => {
  for (const [action, args] of [
    ["setPriority", { bucket: "normal" }],
    ["park", {}],
    ["complete", {}],
    ["delete", {}],
  ]) {
    const m = load(["- [ ] ‼️ Ship the deck"]);
    const it = m.urgent[0];
    applyAction(m, action, { id: it.id, ...args });
    assert.equal(it.must, false, action);
  }
});

test("a bulk move to Normal clears Must on every item", () => {
  const m = load(["- [ ] ‼️ A", "- [ ] ‼️ B"]);
  const ids = m.urgent.map((i) => i.id);
  applyAction(m, "setPriorityMany", { ids, bucket: "normal" });
  assert.equal(countMusts(m), 0);
  assert.equal(m.normal.filter((i) => i.must).length, 0);
});

test("dragging a Must out of the Today list drops the commitment", () => {
  const m = load(["- [ ] ‼️ Ship the deck", "- [ ] Read the spec"]);
  const it = m.urgent[0];
  applyAction(m, "reorderTo", { id: it.id, bucket: "urgent" });
  assert.equal(it.must, false);
  assert.equal(it.starred, false);
});

test("manual reorder cannot cross a rank boundary", () => {
  const m = load(["- [ ] ‼️ A", "- [ ] ⭐ B", "- [ ] C"]);
  reflowUrgent(m);
  const b = m.urgent[1];
  // B is Today; nudging it up would jump the Must group — refused as a no-op.
  assert.equal(applyAction(m, "reorder", { id: b.id, dir: "up" }), null);
  assert.deepEqual(titles(m), ["!A", "*B", "-C"]);
});

test("completing a Must does not leave a ‼️ stranded in Completed", () => {
  const m = load(["- [ ] ‼️ Ship the deck"]);
  applyAction(m, "complete", { id: m.urgent[0].id });
  assert.doesNotMatch(serialize(m), /‼️/);
});
