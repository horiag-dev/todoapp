import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { parseVault } from "../src/parse.mjs";
import { migrate } from "../src/migrate.mjs";
import { serialize } from "../src/serialize.mjs";

const realPath = process.env.REAL_TODO_FILE || join(homedir(), "Downloads", "new_worktodo 14.md");
const present = existsSync(realPath);

test("real working file migrates to expected shape", { skip: !present && "real file not present" }, () => {
  const m = migrate(parseVault(readFileSync(realPath, "utf8")));
  assert.equal(m.urgent.length, 12, "urgent count");
  assert.equal(m.urgent.filter((i) => i.starred).length, 3, "starred count");
  assert.equal(m.normal.length, 41, "normal count");

  const out = serialize(m);
  assert.ok(!/^#+.*today/im.test(out), "no Today section survives");
  assert.ok(!/^#+.*this week/im.test(out), "no This Week section survives");
  assert.ok(out.includes("## 🎯 Goals"), "goals preserved");
});
