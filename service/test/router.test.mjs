import { test } from "node:test";
import assert from "node:assert/strict";
import { routeTier } from "../src/router.mjs";

const tierOf = (args) => routeTier(args).tier;

test("button intents route to the deep tier (Opus, high effort)", () => {
  for (const intent of ["review", "plan", "tidy"]) {
    const r = routeTier({ message: "anything", intent });
    assert.equal(r.tier, "deep");
    assert.equal(r.model, "opus");
    assert.equal(r.effort, "high");
  }
});

test("a pinned single todo with a short instruction is fast (Haiku, no effort)", () => {
  const r = routeTier({ message: "get rid of it", context: { id: "i7", title: "Old thing", bucket: "normal" } });
  assert.equal(r.tier, "fast");
  assert.equal(r.model, "haiku");
  assert.equal(r.effort, undefined);
  assert.equal(r.maxTurns, 8);
});

test("a pinned todo with a heavy instruction escalates to standard", () => {
  assert.equal(tierOf({ message: "reorganize everything around this", context: { id: "i7" } }), "standard");
});

test("short imperative single-item edits are fast", () => {
  assert.equal(tierOf({ message: "delete the milk todo" }), "fast");
  assert.equal(tierOf({ message: "rename it to Buy groceries" }), "fast");
  assert.equal(tierOf({ message: "move the report to normal" }), "fast");
});

test("an incidental heavy keyword in a trivial edit stays fast", () => {
  // "delete" wins over the word "review" appearing later.
  assert.equal(tierOf({ message: "delete the review notes todo" }), "fast");
});

test("chained or multi-step requests are not fast", () => {
  assert.notEqual(tierOf({ message: "delete this and then re-tag the rest" }), "fast");
});

test("heavy keywords route deep", () => {
  assert.equal(tierOf({ message: "help me clean up my urgent list" }), "deep");
  assert.equal(tierOf({ message: "let's do my weekly review" }), "deep");
  assert.equal(tierOf({ message: "reprioritize everything" }), "deep");
});

test("a lot of pasted text routes deep", () => {
  assert.equal(tierOf({ message: "x ".repeat(220) }), "deep");
});

test("a short follow-up inherits the ongoing tier (the 'ok do it' trap)", () => {
  assert.equal(tierOf({ message: "ok do it", prevTier: "deep" }), "deep");
  assert.equal(tierOf({ message: "the second one", prevTier: "deep" }), "deep");
  // ...but a fresh trivial edit still routes fast regardless of history
  assert.equal(tierOf({ message: "delete the milk todo", prevTier: "deep" }), "fast");
  // ...and a short follow-up after a FAST edit is NOT kept on Haiku (inherit up only)
  assert.equal(tierOf({ message: "what about this?", prevTier: "fast" }), "standard");
});

test("uncertain / conversational messages default to standard (Sonnet)", () => {
  assert.equal(tierOf({ message: "what should I focus on this afternoon?" }), "standard");
  assert.equal(routeTier({ message: "hmm" }).model, "sonnet");
});

// --- tool scope (progressive loading) ---------------------------------------
const scopeOf = (args) => routeTier(args).scope;

test("everyday capture and edit stay on the core tool set", () => {
  for (const m of ["add call the dentist", "add milk", "mark i3 today", "complete i7", "delete i4"])
    assert.equal(scopeOf({ message: m }), "core", m);
});

test("reaching past the todo list loads every tool up front", () => {
  for (const m of [
    "what are my goals?", "rewrite my goals", "read my notes on Raj",
    "summarize the attached pdf", "remember I prefer short replies",
    "add a [[Project]] link to i2", "prune my to read list",
  ]) assert.equal(scopeOf({ message: m }), "full", m);
});

test("stems match plurals and inflections, not just bare words", () => {
  // "goal\b" would miss "goals" — the miss costs a whole extra round trip.
  assert.equal(scopeOf({ message: "what are my goals" }), "full");
  assert.equal(scopeOf({ message: "check the attachments" }), "full");
  assert.equal(scopeOf({ message: "summarize that" }), "full");
});

test("deep requests skip the guess and load everything", () => {
  assert.equal(scopeOf({ message: "weekly review" }), "full");
  assert.equal(scopeOf({ intent: "plan", message: "" }), "full");
});

test("a short follow-up keeps the scope its thread was running at", () => {
  assert.equal(scopeOf({ message: "ok do it", prevTier: "standard", prevScope: "full" }), "full");
  // ...but a plain follow-up on a core thread stays core
  assert.equal(scopeOf({ message: "ok do it", prevTier: "standard", prevScope: "core" }), "core");
});
