// The private age ledger: tracks first-seen so the assistant can reason about
// staleness, while the markdown file itself stays date-free.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, existsSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Vault } from "../src/vault.mjs";
import { touch, ageDays } from "../src/ledger.mjs";

const FIXTURE = `# Todo List

### 🔴 Urgent

- [ ] Something

### 🔵 Normal

## 📚 To Read

- https://example.com/old
`;

test("ledger records first-seen and computes age; the .md has no dates", () => {
  const dir = mkdtempSync(join(tmpdir(), "bigrocks-"));
  const doc = join(dir, "todo.md");
  writeFileSync(doc, FIXTURE, "utf8");
  try {
    const vault = new Vault({ todoDocPath: doc });
    const model = vault.load();

    // pretend everything was first seen 40 days ago
    const past = new Date(Date.now() - 40 * 86400000).toISOString();
    const seen = touch(vault, model, past);

    assert.equal(ageDays(seen, "https://example.com/old"), 40);
    assert.equal(ageDays(seen, "Something"), 40);
    assert.equal(ageDays(seen, "never seen this"), null);

    // the ledger lives under .bigrocks, NOT in the markdown
    assert.ok(existsSync(join(dir, ".bigrocks", "seen.json")));
    assert.ok(!/\d{4}-\d{2}-\d{2}/.test(readFileSync(doc, "utf8")), "no ISO dates in the vault file");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("touch is idempotent — re-touching keeps the original first-seen", () => {
  const dir = mkdtempSync(join(tmpdir(), "bigrocks-"));
  const doc = join(dir, "todo.md");
  writeFileSync(doc, FIXTURE, "utf8");
  try {
    const vault = new Vault({ todoDocPath: doc });
    const model = vault.load();
    const past = new Date(Date.now() - 40 * 86400000).toISOString();
    touch(vault, model, past);
    const seen2 = touch(vault, model); // now — should NOT reset existing keys
    assert.equal(ageDays(seen2, "Something"), 40);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
