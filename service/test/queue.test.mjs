// Queues — sequential todos. `↳ ` means "do this after the line directly above
// me". Positional, so there is no graph: no cycles, no orphans, no dangling ids.
import test from "node:test";
import assert from "node:assert/strict";
import { parseVault } from "../src/parse.mjs";
import { migrate } from "../src/migrate.mjs";
import { serialize } from "../src/serialize.mjs";
import { assignIds, reflowUrgent, chainsOf, itemView } from "../src/model.mjs";
import { applyAction } from "../src/ops.mjs";

const doc = (urgent, normal = []) => [
  "# Todo List", "", "## 🎯 Goals", "", "### 🔴 Top 5 of the week", "", "## 📚 To Read", "",
  "### 🔴 Urgent", "", ...urgent, "",
  "### 🔵 Normal", ...(normal.length ? ["", ...normal] : []), "",
  "### ✅ Completed", "", "### 🗑️ Deleted",
].join("\n");
const load = (urgent, normal) => assignIds(migrate(parseVault(doc(urgent, normal))));
const shape = (arr) => arr.map((i) => (i.blocked ? "↳" : i.must ? "!" : i.starred ? "*" : "-") + i.title);
const byTitle = (m, b, t) => m[b].find((i) => i.title === t).id;

// --- file format -------------------------------------------------------------

test("↳ parses as queued and round-trips byte-identically", () => {
  const src = doc(["- [ ] Book the venue", "- [ ] ↳ Send invites", "- [ ] ↳ Print badges"]) + "\n";
  const m = migrate(parseVault(src));
  assert.deepEqual(m.urgent.map((i) => !!i.blocked), [false, true, true]);
  assert.equal(serialize(m), src);
});

test("a queued item can't also be Today or Must — the chain marker wins", () => {
  const m = load(["- [ ] Head", "- [ ] ↳ ⭐ Second", "- [ ] ↳ ‼️ Third"]);
  for (const it of m.urgent.slice(1)) {
    assert.equal(it.blocked, true, it.title);
    assert.equal(!!it.starred, false, it.title);
    assert.equal(!!it.must, false, it.title);
  }
  assert.doesNotMatch(serialize(m), /⭐|‼️/);
});

test("titles stay verbatim through the queue marker", () => {
  const m = load(["- [ ] Head", "- [ ] ↳ Ping [[Raj]] about #launch"]);
  assert.equal(m.urgent[1].title, "Ping [[Raj]] about #launch");
});

// --- structure ---------------------------------------------------------------

test("a leading ↳ is dropped — nothing sits above the first line to wait for", () => {
  const m = load(["- [ ] ↳ Orphan", "- [ ] Second"]);
  reflowUrgent(m);
  assert.equal(!!m.urgent[0].blocked, false);
});

test("chainsOf groups a head with its consecutive followers", () => {
  const m = load(["- [ ] A", "- [ ] ↳ A2", "- [ ] ↳ A3", "- [ ] B", "- [ ] ↳ B2"]);
  assert.deepEqual(chainsOf(m.urgent).map((c) => c.map((i) => i.title)), [["A", "A2", "A3"], ["B", "B2"]]);
});

test("a queue survives reflow as a unit, ranked by its head", () => {
  // Head is plain, follower is queued; a Today item should sort ABOVE the whole
  // queue rather than landing between the head and its follower.
  const m = load(["- [ ] Ship the deck", "- [ ] ↳ Send it round", "- [ ] ⭐ Call Raj"]);
  reflowUrgent(m);
  assert.deepEqual(shape(m.urgent), ["*Call Raj", "-Ship the deck", "↳Send it round"]);
});

test("promoting a queue head to Must carries the queue to the top intact", () => {
  const m = load(["- [ ] ⭐ Call Raj", "- [ ] Ship the deck", "- [ ] ↳ Send it round"]);
  applyAction(m, "toggleMust", { id: byTitle(m, "urgent", "Ship the deck") });
  assert.deepEqual(shape(m.urgent), ["!Ship the deck", "↳Send it round", "*Call Raj"]);
});

// --- the head completing releases the next --------------------------------

test("completing the head promotes the next item in the queue", () => {
  const m = load(["- [ ] Book the venue", "- [ ] ↳ Send invites", "- [ ] ↳ Print badges"]);
  applyAction(m, "complete", { id: byTitle(m, "urgent", "Book the venue") });
  assert.deepEqual(shape(m.urgent), ["-Send invites", "↳Print badges"]);
  // …and the completed copy carries no stale marker into the archive
  assert.equal(!!m.completed[0].blocked, false);
  assert.doesNotMatch(serialize(m).split("### ✅")[1], /↳/);
});

test("deleting or parking the head also releases the next", () => {
  for (const action of ["delete", "park"]) {
    const m = load(["- [ ] Head", "- [ ] ↳ Next"]);
    applyAction(m, action, { id: byTitle(m, "urgent", "Head") });
    assert.equal(!!m.urgent[0].blocked, false, action);
  }
});

test("moving the head to Normal releases the follower left behind", () => {
  const m = load(["- [ ] Head", "- [ ] ↳ Next"]);
  applyAction(m, "setPriority", { id: byTitle(m, "urgent", "Head"), bucket: "normal" });
  assert.equal(m.urgent.length, 1);
  assert.equal(!!m.urgent[0].blocked, false);
  assert.equal(!!m.normal.at(-1).blocked, false, "the moved item isn't queued in its new home either");
});

// --- toggling ----------------------------------------------------------------

test("toggleQueued queues behind the item above, and releases again", () => {
  const m = load(["- [ ] First", "- [ ] Second"]);
  const id = byTitle(m, "urgent", "Second");
  assert.match(applyAction(m, "toggleQueued", { id }), /queued "Second" after "First"/);
  assert.equal(m.urgent[1].blocked, true);
  assert.match(applyAction(m, "toggleQueued", { id }), /released/);
  assert.equal(m.urgent[1].blocked, false);
});

test("the first item in a section can't be queued — nothing to wait for", () => {
  const m = load(["- [ ] Only", "- [ ] Second"]);
  assert.throws(() => applyAction(m, "toggleQueued", { id: byTitle(m, "urgent", "Only") }), /nothing above this/);
});

test("queuing an item clears Today and Must — it isn't startable", () => {
  const m = load(["- [ ] ‼️ Head", "- [ ] ‼️ Committed"]);
  applyAction(m, "toggleQueued", { id: byTitle(m, "urgent", "Committed") });
  const it = m.urgent.find((i) => i.title === "Committed");
  assert.equal(it.blocked, true);
  assert.equal(!!it.must, false);
  assert.equal(!!it.starred, false);
});

test("marking a queued item Today releases it from the queue", () => {
  const m = load(["- [ ] Head", "- [ ] ↳ Next"]);
  applyAction(m, "toggleToday", { id: byTitle(m, "urgent", "Next") });
  const it = m.urgent.find((i) => i.title === "Next");
  assert.equal(it.starred, true);
  assert.equal(!!it.blocked, false, "you can't intend to do today something you've said is blocked");
});

// --- dragging ----------------------------------------------------------------

test("dragging a queue head carries its followers", () => {
  const m = load(["- [ ] Other", "- [ ] Head", "- [ ] ↳ A", "- [ ] ↳ B"]);
  applyAction(m, "reorderTo", {
    id: byTitle(m, "urgent", "Head"), bucket: "urgent",
    targetId: byTitle(m, "urgent", "Other"), position: "before",
  });
  assert.deepEqual(shape(m.urgent), ["-Head", "↳A", "↳B", "-Other"]);
});

test("dragging a follower out detaches just that one", () => {
  const m = load(["- [ ] Head", "- [ ] ↳ A", "- [ ] ↳ B"]);
  applyAction(m, "reorderTo", {
    id: byTitle(m, "urgent", "A"), bucket: "urgent", targetId: null, position: "after",
  });
  assert.deepEqual(shape(m.urgent), ["-Head", "↳B", "-A"]);
});

test("the up/down nudge moves a whole queue, and a follower has no nudge of its own", () => {
  const m = load(["- [ ] Head", "- [ ] ↳ A", "- [ ] Other"]);
  assert.equal(applyAction(m, "reorder", { id: byTitle(m, "urgent", "A"), dir: "up" }), null);
  applyAction(m, "reorder", { id: byTitle(m, "urgent", "Head"), dir: "down" });
  assert.deepEqual(shape(m.urgent), ["-Other", "-Head", "↳A"]);
});

// --- what the UI and the agent see -------------------------------------------

test("a queued item reports what it is waiting for", () => {
  const m = load(["- [ ] Book the venue", "- [ ] ↳ Send invites"]);
  const v = m.urgent.map((it, i) => itemView(it, m.urgent, i));
  assert.equal(v[0].blocked, undefined);
  assert.equal(v[1].blocked, true);
  assert.equal(v[1].waitingFor, "Book the venue");
});

test("the second follower waits on the head, not on the item above it", () => {
  const m = load(["- [ ] Head", "- [ ] ↳ A", "- [ ] ↳ B"]);
  const v = m.urgent.map((it, i) => itemView(it, m.urgent, i));
  assert.equal(v[2].waitingFor, "Head");
});

// --- un-complete -------------------------------------------------------------

test("uncomplete puts a mis-clicked todo back in Urgent, unchecked", () => {
  const m = load(["- [ ] Real work"]);
  const id = byTitle(m, "urgent", "Real work");
  applyAction(m, "complete", { id });
  assert.equal(m.completed.length, 1);
  assert.match(applyAction(m, "uncomplete", { id }), /back in Urgent/);
  assert.equal(m.completed.length, 0);
  assert.equal(m.urgent[0].title, "Real work");
  assert.equal(m.urgent[0].checked, false);
  assert.doesNotMatch(serialize(m), /- \[x\]/);
});

test("uncomplete refuses anything that isn't completed", () => {
  const m = load(["- [ ] Active"]);
  assert.throws(() => applyAction(m, "uncomplete", { id: byTitle(m, "urgent", "Active") }), /only completed/);
});

test("completing a head that ISN'T first still releases its follower, not re-points it", () => {
  // The trap in positional chaining: remove "Book the venue" and "Send invites"
  // would slide up under "Call Raj" and silently start waiting on THAT.
  const m = load(["- [ ] ⭐ Call Raj", "- [ ] Book the venue", "- [ ] ↳ Send invites", "- [ ] ↳ Print badges"]);
  applyAction(m, "complete", { id: byTitle(m, "urgent", "Book the venue") });
  assert.deepEqual(shape(m.urgent), ["*Call Raj", "-Send invites", "↳Print badges"]);
  const v = m.urgent.map((it, i) => itemView(it, m.urgent, i));
  assert.equal(v[2].waitingFor, "Send invites", "the tail still waits on its own predecessor");
});

test("only the direct follower is promoted — the rest of the queue stays queued", () => {
  const m = load(["- [ ] A", "- [ ] ↳ B", "- [ ] ↳ C", "- [ ] ↳ D"]);
  applyAction(m, "complete", { id: byTitle(m, "urgent", "A") });
  assert.deepEqual(shape(m.urgent), ["-B", "↳C", "↳D"]);
});

test("deleting a mid-queue item closes the gap without orphaning the tail", () => {
  const m = load(["- [ ] A", "- [ ] ↳ B", "- [ ] ↳ C"]);
  applyAction(m, "delete", { id: byTitle(m, "urgent", "B") });
  // C was waiting on B; with B gone it becomes the head's direct follower.
  assert.deepEqual(shape(m.urgent), ["-A", "-C"]);
});
