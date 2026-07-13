// Local server (loopback only). The agent works on an in-memory DRAFT of the
// vault; nothing is written to disk until the user clicks Apply.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { Vault } from "./vault.mjs";
import { assignIds, itemView } from "./model.mjs";
import { runAgent } from "./agent.mjs";
import { touch, ageDays } from "./ledger.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT) || 5178;
const HOST = "127.0.0.1";

const todoDocPath = process.env.TODO_FILE;
if (!todoDocPath) {
  console.error("Set TODO_FILE to the vault todo document.");
  process.exit(2);
}
const vault = new Vault({ todoDocPath });

// --- session state (single local user) ---
let working = assignIds(vault.load());
let ops = []; // pending change descriptions since last apply/discard
let seen = touch(vault, working); // private first-seen ledger (for staleness)
let sessionId; // claude-agent-sdk session (multi-turn context)
let busy = false;

function reload() {
  working = assignIds(vault.load());
  ops = [];
  seen = touch(vault, working);
}

function modelView() {
  const ageOf = (text) => { const a = ageDays(seen, text); return a != null && a >= 7 ? a : null; };
  const view = (it) => ({ ...itemView(it), age: ageOf(it.title) });
  return {
    todoDocPath,
    dirty: ops.length > 0,
    ops,
    goals: working.goals?.rawLines ?? [],
    toread: (working.toread?.rawLines ?? []).map((l) => {
      const t = l.replace(/^-\s+/, "").trim();
      return { text: t, age: ageOf(t) };
    }),
    top5: working.top5.map(view),
    urgent: working.urgent.map(view),
    normal: working.normal.map(view),
    completed: working.completed.length,
    deleted: working.deleted.length,
  };
}

const json = (res, status, obj) => { res.writeHead(status, { "content-type": "application/json" }); res.end(JSON.stringify(obj)); };
const readBody = (req) => new Promise((resolve) => { let b = ""; req.on("data", (c) => (b += c)); req.on("end", () => resolve(b ? JSON.parse(b) : {})); });

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${HOST}`);
    const p = url.pathname;

    if (req.method === "GET" && p === "/") {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      return res.end(await readFile(join(here, "..", "public", "index.html")));
    }
    if (req.method === "GET" && p === "/api/model") return json(res, 200, modelView());

    if (req.method === "POST" && p === "/api/chat") {
      if (busy) return json(res, 409, { error: "busy" });
      const { message } = await readBody(req);
      if (!message?.trim()) return json(res, 400, { error: "empty message" });
      busy = true;
      try {
        const before = ops.length;
        const { reply, sessionId: sid } = await runAgent({ model: working, ops, seen, message, sessionId });
        sessionId = sid;
        return json(res, 200, { reply, model: modelView(), newOps: ops.slice(before) });
      } finally {
        busy = false;
      }
    }
    if (req.method === "POST" && p === "/api/apply") {
      vault.save(working, { op: "agent" });
      reload();
      return json(res, 200, { ok: true, model: modelView() });
    }
    if (req.method === "POST" && p === "/api/discard") {
      reload();
      return json(res, 200, { ok: true, model: modelView() });
    }
    return json(res, 404, { error: "not found" });
  } catch (err) {
    console.error(err);
    return json(res, 500, { error: String(err?.message || err) });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Big Rocks First — http://${HOST}:${PORT}`);
  console.log(`vault doc: ${todoDocPath}`);
});
