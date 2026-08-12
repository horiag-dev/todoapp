import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { parseVault } from "../src/parse.mjs";
import { migrate } from "../src/migrate.mjs";
import { serialize } from "../src/serialize.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const fixture = readFileSync(join(here, "..", "fixtures", "obsidian-roundtrip.md"), "utf8");

test("Obsidian round-trip is byte-identical (frontmatter + [[links]] + #tags preserved)", () => {
  const out = serialize(migrate(parseVault(fixture)));
  assert.equal(out, fixture);
});

test("serialize is idempotent", () => {
  const once = serialize(migrate(parseVault(fixture)));
  const twice = serialize(migrate(parseVault(once)));
  assert.equal(twice, once);
});
