import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createMemory, loadMemory, injectionText, LIMITS } from "../src/memory.mjs";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "bigrocks-mem-"));
  return { dir, vault: { memoryPath: join(dir, "Assistant Memory.md"), machineDir: join(dir, ".bigrocks") } };
}
const clean = (f) => rmSync(f.dir, { recursive: true, force: true });

test("remember creates the note, dedupes, and preserves hand-written prose", () => {
  const f = fixture();
  try {
    const mem = createMemory(f.vault);
    assert.match(mem.append("How I should behave", "Keep replies short"), /Remembered/);
    assert.ok(existsSync(f.vault.memoryPath));
    assert.match(mem.append("How I should behave", "keep replies   short"), /Already remembered/); // case/space-insensitive NOOP

    // The user hand-edits the note in Obsidian: prose + a bullet + a sub-bullet.
    let raw = readFileSync(f.vault.memoryPath, "utf8")
      .replace("## About you & your work\n", "## About you & your work\nSome freeform note I wrote.\n- Works at Acme\n  - sub detail\n");
    writeFileSync(f.vault.memoryPath, raw, "utf8");
    mem.append("About you & your work", "Reviews on Sundays");
    const after = readFileSync(f.vault.memoryPath, "utf8");
    assert.match(after, /Some freeform note I wrote\./); // prose preserved
    assert.match(after, /\n {2}- sub detail/);           // sub-bullet preserved verbatim
    assert.match(after, /- Reviews on Sundays/);          // new bullet added
  } finally { clean(f); }
});

test("guards reject secrets, dates, and over-long bullets (nothing written)", () => {
  const f = fixture();
  try {
    const mem = createMemory(f.vault);
    assert.match(mem.append("About you & your work", "my api_key is abc123"), /secret|credential/i);
    assert.match(mem.append("About you & your work", "renovation ends 2026-09-01"), /date-free/i);
    assert.match(mem.append("About you & your work", "x".repeat(LIMITS.bulletChars + 1)), /Too long/);
    assert.ok(!existsSync(f.vault.memoryPath));
  } finally { clean(f); }
});

test("update and forget require a unique match", () => {
  const f = fixture();
  try {
    const mem = createMemory(f.vault);
    mem.append("How I should behave", "Reuse existing tags");
    mem.append("How I should behave", "Reuse the weekly cadence");
    assert.match(mem.replace("Reuse", "x"), /matches 2/);            // ambiguous
    assert.match(mem.replace("nothing here", "x"), /No memory matches/);
    assert.match(mem.replace("existing tags", "Reuse #house and #work only"), /Updated/);
    assert.match(readFileSync(f.vault.memoryPath, "utf8"), /Reuse #house and #work only/);
    assert.match(mem.remove("weekly cadence"), /Forgotten/);
    assert.doesNotMatch(readFileSync(f.vault.memoryPath, "utf8"), /weekly cadence/);
  } finally { clean(f); }
});

test("meta sweep stamps user-typed bullets and drops orphans", () => {
  const f = fixture();
  try {
    const mem = createMemory(f.vault);
    mem.append("How I should behave", "Agent added rule");
    let raw = readFileSync(f.vault.memoryPath, "utf8").replace("- Agent added rule", "- Agent added rule\n- Hand typed rule");
    writeFileSync(f.vault.memoryPath, raw, "utf8");
    const loaded = loadMemory(f.vault);
    assert.equal(loaded.bullets.find((b) => b.text === "Hand typed rule").source, "user-edited");
    assert.equal(loaded.bullets.find((b) => b.text === "Agent added rule").source, "user-said");

    // User deletes the agent bullet by hand → its meta entry is dropped on next load.
    writeFileSync(f.vault.memoryPath, readFileSync(f.vault.memoryPath, "utf8").replace("- Agent added rule\n", ""), "utf8");
    loadMemory(f.vault);
    const meta = JSON.parse(readFileSync(join(f.vault.machineDir, "memory-meta.json"), "utf8"));
    assert.ok(!Object.keys(meta).some((k) => k.includes("agent added rule")));
  } finally { clean(f); }
});

test("injection stays under budget by trimming Working notes first", () => {
  const f = fixture();
  try {
    // Hand-grown file (agent caps can't produce this) to force truncation.
    const working = Array.from({ length: 80 }, (_, i) => `- working observation ${i} padded out to a decently long line about something`).join("\n");
    writeFileSync(f.vault.memoryPath,
      `# Assistant Memory\n\n## How I should behave\n- A durable rule that must always survive injection\n\n## Working notes\n${working}\n`, "utf8");
    const inj = injectionText(f.vault);
    assert.ok(inj.length <= LIMITS.injectChars, `injection ${inj.length} > ${LIMITS.injectChars}`);
    assert.match(inj, /durable rule that must always survive/i); // priority section kept whole
    assert.match(inj, /more — read_memory/);                     // working notes truncated with a marker
  } finally { clean(f); }
});
