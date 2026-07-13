import {
  readFileSync,
  existsSync,
  mkdirSync,
  copyFileSync,
  appendFileSync,
  readdirSync,
  rmSync,
  statSync,
  renameSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { join, dirname, basename, extname } from "node:path";
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
  // User documents live as ordinary files in the vault (Obsidian sees them).
  get attachmentsDir() {
    return join(this.vaultPath, "attachments");
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

  // Snapshots, newest last (timestamps are lexicographically chronological).
  #snapshots() {
    try {
      return readdirSync(this.historyDir)
        .filter((f) => f.endsWith(".md"))
        .sort();
    } catch {
      return [];
    }
  }

  hasHistory() {
    return this.#snapshots().length > 0;
  }

  // Restore the newest snapshot and pop it, giving multi-step undo. We restore
  // WITHOUT taking a new snapshot so repeated undo walks back through history
  // rather than piling on new entries. Returns {content, version} or null.
  undo() {
    const snaps = this.#snapshots();
    if (!snaps.length) return null;
    const newest = snaps[snaps.length - 1];
    const snapPath = join(this.historyDir, newest);
    const content = readFileSync(snapPath, "utf8");
    writeFileAtomic(this.todoDocPath, content);
    rmSync(snapPath, { force: true });
    appendFileSync(
      this.logPath,
      JSON.stringify({ at: new Date().toISOString(), op: "undo", restored: newest }) + "\n",
    );
    return { content, version: digest(content) };
  }

  // --- Attachments: files the user drops in, kept in <vault>/attachments -------
  #safeAttachmentName(name) {
    const base = basename(String(name ?? "")).replace(/^\.+/, "").trim();
    if (!base || base.includes("/") || base.includes("\\")) throw new Error("Invalid attachment name.");
    return base;
  }

  #uniqueAttachmentPath(name) {
    let candidate = join(this.attachmentsDir, name);
    if (!existsSync(candidate)) return candidate;
    const ext = extname(name);
    const stem = name.slice(0, name.length - ext.length);
    for (let i = 2; ; i++) {
      candidate = join(this.attachmentsDir, `${stem} (${i})${ext}`);
      if (!existsSync(candidate)) return candidate;
    }
  }

  listAttachments() {
    let names;
    try { names = readdirSync(this.attachmentsDir); } catch { return []; }
    return names
      .filter((f) => !f.startsWith("."))
      .map((f) => {
        try {
          const s = statSync(join(this.attachmentsDir, f));
          return s.isFile() ? { name: f, size: s.size, mtime: s.mtimeMs } : null;
        } catch { return null; }
      })
      .filter(Boolean)
      .sort((a, b) => b.mtime - a.mtime);
  }

  saveAttachment(name, data) {
    const safe = this.#safeAttachmentName(name);
    mkdirSync(this.attachmentsDir, { recursive: true });
    const target = this.#uniqueAttachmentPath(safe);
    writeFileAtomic(target, data);
    return basename(target);
  }

  readAttachment(name) {
    const p = join(this.attachmentsDir, this.#safeAttachmentName(name));
    return existsSync(p) ? readFileSync(p) : null;
  }

  // Removal is recoverable: move to .bigrocks/trash rather than hard-delete.
  removeAttachment(name) {
    const safe = this.#safeAttachmentName(name);
    const p = join(this.attachmentsDir, safe);
    if (!existsSync(p)) return false;
    const trash = join(this.machineDir, "trash");
    mkdirSync(trash, { recursive: true });
    const ts = new Date().toISOString().replace(/[:.]/g, "-");
    renameSync(p, join(trash, `${ts}__${safe}`));
    return true;
  }
}
