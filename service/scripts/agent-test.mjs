import { Vault } from "../src/vault.mjs";
import { assignIds } from "../src/model.mjs";
import { runAgent } from "../src/agent.mjs";

const vault = new Vault({ todoDocPath: process.env.TODO_FILE });
const model = assignIds(vault.load());
const ops = [];
const message =
  process.argv[2] ||
  'Add "Call the bank" to urgent and mark it Today. Also complete the urgent item about "Sunil asks".';

console.log("USER:", message, "\n");
const { reply } = await runAgent({ model, ops, message });
console.log("REPLY:", reply, "\n");
console.log("OPS:", JSON.stringify(ops, null, 0), "\n");
console.log("urgent (top 6):");
for (const i of model.urgent.slice(0, 6)) console.log(`  ${i.starred ? "Today" : "     "}  ${i.title}`);
console.log("completed count:", model.completed.length);
