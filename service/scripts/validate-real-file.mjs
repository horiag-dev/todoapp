// Validate the parser/migration against a real file and print a report.
// Usage: node scripts/validate-real-file.mjs ["/path/to/todo.md"]
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { parseVault } from "../src/parse.mjs";
import { migrate, cleanHack } from "../src/migrate.mjs";
import { serialize } from "../src/serialize.mjs";

const path = process.argv[2] || join(homedir(), "Downloads", "new_worktodo 14.md");
if (!existsSync(path)) {
  console.error(`File not found: ${path}`);
  process.exit(2);
}

const raw = readFileSync(path, "utf8");
const parsed = parseVault(raw);
const m = migrate(parsed);

const before = {};
for (const s of parsed.sections) before[s.kind] = (before[s.kind] ?? 0) + (s.items?.length ?? 0);

console.log(`\nSource: ${path}\n`);
console.log("Before (legacy buckets):");
for (const k of ["top5", "today", "urgent", "thisweek", "normal", "completed", "deleted"]) {
  if (before[k]) console.log(`  ${k.padEnd(10)} ${before[k]}`);
}
console.log("\nAfter (migrated model):");
console.log(`  urgent     ${m.urgent.length}  (${m.urgent.filter((i) => i.starred).length} starred)`);
console.log(`  normal     ${m.normal.length}`);
console.log(`  top5       ${m.top5.length}`);
console.log(`  completed  ${m.completed.length}`);
console.log(`  deleted    ${m.deleted.length}`);
console.log(`  goals      ${m.goals ? "preserved" : "—"}`);
console.log(`  to read    ${m.toread ? `preserved (${m.toread.rawLines.length} lines)` : "—"}`);

const marked = m.urgent.filter((i) => i.must || i.starred || i.blocked);
if (marked.length) {
  console.log(`\nMarked items:`);
  for (const i of marked) console.log(`  ${i.must ? "‼️" : i.blocked ? "↳ " : "⭐"} ${i.title}`);
}

const out = serialize(m);
const twice = serialize(migrate(parseVault(out)));

// Real invariants, not fixture-specific counts. The previous version asserted the
// item counts of one particular 2026 snapshot ("urgent == 12"), so it reported FAIL
// on every other file — including the user's current one — which made the whole
// tool untrustworthy. What actually matters is that nothing is lost or churned.
const bodyLines = (t) => t.split("\n").filter((l) => /^- \[[ xX]\]/.test(l)).length;
// A migrated line legitimately CHANGES (the TODA[Yy] hack is stripped into a ⭐, a
// marker is normalized), so compare on the cleaned remainder rather than the raw
// text — otherwise migration itself looks like data loss.
const core = (l) => cleanHack(l.replace(/^- \[[ xX]\]\s*/, "").replace(/^(?:⭐️?|‼️?|↳)[ \t]*/g, "")).trim();
const outCores = new Set(out.split("\n").map(core).filter(Boolean));
const lost = raw.split("\n")
  .filter((l) => l.trim() && !l.startsWith("#"))
  .filter((l) => !out.includes(l.trim()) && !outCores.has(core(l)));
const checks = [
  ["every todo line survives", bodyLines(out) === bodyLines(raw)],
  ["no non-header line dropped", lost.length === 0],
  ["serializing is idempotent", out === twice],
  ["no legacy Today section left", !/^#+.*today/im.test(out)],
  ["no legacy This Week section left", !/^#+.*this week/im.test(out)],
  ["goals preserved", !raw.includes("## 🎯 Goals") || out.includes("## 🎯 Goals")],
];
if (out === raw) console.log("\n✓ round-trips BYTE-IDENTICAL (already in current format)");
else console.log(`\n· rewritten: ${bodyLines(raw)} todo lines in, ${bodyLines(out)} out`);
if (lost.length) {
  console.log("\n  Lines that would be lost:");
  for (const l of lost.slice(0, 10)) console.log(`    - ${l.slice(0, 100)}`);
}
console.log("\nChecks:");
let ok = true;
for (const [label, pass] of checks) {
  console.log(`  ${pass ? "✓" : "✗"} ${label}`);
  if (!pass) ok = false;
}
console.log(ok ? "\nPASS\n" : "\nFAIL\n");
process.exit(ok ? 0 : 1);
