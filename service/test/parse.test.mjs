import { test } from "node:test";
import assert from "node:assert/strict";
import { parseVault, classify, tagsOf, linksOf } from "../src/parse.mjs";

test("classify recognizes buckets by name (emoji-agnostic)", () => {
  assert.equal(classify("🔴 Top 5 of the week"), "top5");
  assert.equal(classify("🔴 Urgent"), "urgent");
  assert.equal(classify("🟡 Urgent"), "urgent"); // parser-fallback fix
  assert.equal(classify("Urgent"), "urgent"); // hand-typed, no emoji
  assert.equal(classify("☀️ Today"), "today");
  assert.equal(classify("🟠 This Week"), "thisweek");
  assert.equal(classify("🔵 Normal"), "normal");
  assert.equal(classify("⚪ When there's time"), "normal");
  assert.equal(classify("✅ Completed"), "completed");
  assert.equal(classify("🗑️ Deleted"), "deleted");
  assert.equal(classify("🎯 Goals"), "goals");
  assert.equal(classify("📚 To Read"), "toread");
});

test("star prefix parsed; title kept verbatim (wikilinks + tags intact)", () => {
  const doc = [
    "# Todo List",
    "",
    "### 🔴 Urgent",
    "",
    "- [ ] ⭐ Reply to [[Investor Update]] #fundraising",
    "- [x] Approve assets #launch",
  ].join("\n");
  const { sections } = parseVault(doc);
  const urgent = sections.find((s) => s.kind === "urgent");
  assert.equal(urgent.items.length, 2);
  assert.deepEqual(urgent.items[0], {
    checked: false,
    must: false,
    blocked: false,
    starred: true,
    title: "Reply to [[Investor Update]] #fundraising",
  });
  assert.deepEqual(urgent.items[1], {
    checked: true,
    must: false,
    blocked: false,
    starred: false,
    title: "Approve assets #launch",
  });
});

test("preamble (frontmatter + title) captured; goals preserved raw", () => {
  const doc = [
    "---",
    "title: X",
    "---",
    "",
    "# Todo List",
    "",
    "## 🎯 Goals",
    "",
    "- a goal",
  ].join("\n");
  const { preamble, sections } = parseVault(doc);
  assert.equal(preamble, "---\ntitle: X\n---\n\n# Todo List");
  const goals = sections.find((s) => s.kind === "goals");
  assert.deepEqual(goals.rawLines, ["- a goal"]);
});

test("derived tag view uses the ' #tag' rule (URL fragments are not tags)", () => {
  assert.deepEqual(tagsOf("Reply #a to [[Note]] #b/c"), ["a", "b/c"]);
  assert.deepEqual(tagsOf("see https://x.com/#section done"), []);
  assert.deepEqual(linksOf("edit [[Note One]] and [[Note Two]]"), ["Note One", "Note Two"]);
});
