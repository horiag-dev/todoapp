// TEST HELPER — backdate the age ledger so staleness behavior can be exercised
// before real time has passed. Sets first-seen of all current To Read entries
// to N days ago. Usage: TODO_FILE=... node scripts/seed-ages.mjs [days]
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { Vault } from "../src/vault.mjs";
import { assignIds } from "../src/model.mjs";
import { loadSeen, keyOf } from "../src/ledger.mjs";

const days = Number(process.argv[2] || 40);
const vault = new Vault({ todoDocPath: process.env.TODO_FILE });
const model = assignIds(vault.load());
const seen = loadSeen(vault);
const iso = new Date(Date.now() - days * 86400000).toISOString();
let n = 0;
for (const l of model.toread?.rawLines ?? []) {
  const t = l.replace(/^-\s+/, "").trim();
  if (t) { seen[keyOf(t)] = iso; n++; }
}
mkdirSync(vault.machineDir, { recursive: true });
writeFileSync(join(vault.machineDir, "seen.json"), JSON.stringify(seen), "utf8");
console.log(`Backdated ${n} To Read entries to ${days}d ago.`);
