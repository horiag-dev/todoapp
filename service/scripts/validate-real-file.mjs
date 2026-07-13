// Validate the parser/migration against a real file and print a report.
// Usage: node scripts/validate-real-file.mjs ["/path/to/todo.md"]
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { parseVault } from "../src/parse.mjs";
import { migrate } from "../src/migrate.mjs";
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

const stars = m.urgent.filter((i) => i.starred).map((i) => i.title);
console.log(`\nStarred (from the TODAY- hack, cleaned):`);
for (const t of stars) console.log(`  ⭐ ${t}`);

const out = serialize(m);
const checks = [
  ["urgent == 12", m.urgent.length === 12],
  ["starred == 3", m.urgent.filter((i) => i.starred).length === 3],
  ["normal == 41", m.normal.length === 41],
  ["no Today section", !/^#+.*today/im.test(out)],
  ["no This Week section", !/^#+.*this week/im.test(out)],
  ["goals preserved", out.includes("## 🎯 Goals")],
];
console.log("\nChecks:");
let ok = true;
for (const [label, pass] of checks) {
  console.log(`  ${pass ? "✓" : "✗"} ${label}`);
  if (!pass) ok = false;
}
console.log(ok ? "\nPASS\n" : "\nFAIL\n");
process.exit(ok ? 0 : 1);
