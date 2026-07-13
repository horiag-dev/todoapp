// End-to-end demo: migrate a todo file through the Vault (parse → migrate →
// serialize → atomic write + history snapshot). Operates on a copy; never
// touches the source. Usage: node scripts/migrate-file.mjs <src.md> <vaultDir>
import { mkdirSync, copyFileSync } from "node:fs";
import { join } from "node:path";
import { Vault } from "../src/vault.mjs";

const [src, vaultDir] = process.argv.slice(2);
if (!src || !vaultDir) {
  console.error("usage: node scripts/migrate-file.mjs <src.md> <vaultDir>");
  process.exit(2);
}

mkdirSync(vaultDir, { recursive: true });
const todoDoc = join(vaultDir, "todo.md");
copyFileSync(src, todoDoc);

const vault = new Vault({ vaultPath: vaultDir, todoDocPath: todoDoc });
const model = vault.load();
vault.save(model, { op: "migrate" });
console.log(`Migrated copy written to ${todoDoc}`);
console.log(`History + log under ${vault.machineDir}`);
