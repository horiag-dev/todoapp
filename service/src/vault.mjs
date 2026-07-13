import {
  readFileSync,
  existsSync,
  mkdirSync,
  copyFileSync,
  appendFileSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { join, dirname, basename } from "node:path";
import { parseVault } from "./parse.mjs";
import { migrate } from "./migrate.mjs";
import { serialize } from "./serialize.mjs";
import { writeFileAtomic } from "./fsAtomic.mjs";

export class VaultConflictError extends Error {
  constructor() {
    super("The todo file changed outside Big Rocks First. Reload before applying changes.");
    this.name = "VaultConflictError";
    this.code = "VAULT_CONFLICT";
  }
}

const digest = (content) => createHash("sha256").update(content).digest("hex");

// The vault-aware foundation: the service targets a vault DIRECTORY plus one
// active document (the todo doc). A second module later registers another
// document against the same Vault — additive, not a rewrite.
//
// Machinery (history snapshots, operation log) lives hidden under `.bigrocks/`.
// Human-facing memory will live as an ordinary visible note elsewhere in the
// vault (not this module's concern in Phase 0).
export class Vault {
  constructor({ vaultPath, todoDocPath }) {
    this.vaultPath = vaultPath;
    this.todoDocPath = todoDocPath ?? join(vaultPath, "todo.md");
    if (!vaultPath) this.vaultPath = dirname(this.todoDocPath);
  }

  get machineDir() {
    return join(this.vaultPath, ".bigrocks");
  }
  get historyDir() {
    return join(this.machineDir, "history");
  }
  get logPath() {
    return join(this.machineDir, "log.jsonl");
  }

  readRaw() {
    return readFileSync(this.todoDocPath, "utf8");
  }

  version() {
    return digest(this.readRaw());
  }

  // Parse + migrate the todo doc into the canonical model.
  load() {
    return migrate(parseVault(this.readRaw()));
  }

  loadVersioned() {
    const content = this.readRaw();
    return { model: migrate(parseVault(content)), version: digest(content) };
  }

  // Serialize the model and write it back, snapshotting the previous file first.
  save(model, { op = "write", expectedVersion } = {}) {
    if (expectedVersion && this.version() !== expectedVersion) throw new VaultConflictError();
    const content = serialize(model);
    this.#snapshot(op);
    writeFileAtomic(this.todoDocPath, content);
    return { content, version: digest(content) };
  }

  #snapshot(op) {
    if (!existsSync(this.todoDocPath)) return;
    mkdirSync(this.historyDir, { recursive: true });
    const ts = new Date().toISOString().replace(/[:.]/g, "-");
    const snap = join(this.historyDir, `${ts}.md`);
    copyFileSync(this.todoDocPath, snap);
    appendFileSync(
      this.logPath,
      JSON.stringify({ at: new Date().toISOString(), op, snapshot: basename(snap) }) + "\n",
    );
  }
}
