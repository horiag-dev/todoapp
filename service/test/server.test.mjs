import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createBigRocksServer } from "../src/server.mjs";

const FILE = `# Todo List

### 🔴 Urgent

- [ ] Existing

### 🔵 Normal

### ✅ Completed

### 🗑️ Deleted
`;

async function fixture(agentRunner) {
  const dir = mkdtempSync(join(tmpdir(), "bigrocks-server-"));
  const doc = join(dir, "todo.md");
  writeFileSync(doc, FILE, "utf8");
  const server = createBigRocksServer({ initialTodoDocPath: doc, agentRunner });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = async (path, body) => {
    const response = await fetch(base + path, {
      method: body === undefined ? "GET" : "POST",
      headers: { "content-type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { response, body: await response.json() };
  };
  return { dir, doc, server, request };
}

test("HTTP direct edits persist and external changes auto-reload", async () => {
  const f = await fixture();
  try {
    let result = await f.request("/api/act", { action: "add", title: "Via API", bucket: "normal" });
    assert.equal(result.response.status, 200);
    assert.match(readFileSync(f.doc, "utf8"), /Via API/);

    writeFileSync(f.doc, FILE.replace("Existing", "Changed outside"), "utf8");
    result = await f.request("/api/model");
    assert.equal(result.body.urgent[0].title, "Changed outside");
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("assistant drafts block direct edits and conflict after an external write", async () => {
  // A large change set (> 3) is held for review rather than auto-applied.
  const fakeAgent = async ({ model, ops }) => {
    for (const t of ["Assistant change", "Two", "Three", "Four"]) {
      model.normal.push({ id: "f-" + t, title: t, checked: false, starred: false });
      ops.push("added " + t);
    }
    return { reply: "Proposed.", sessionId: "test" };
  };
  const f = await fixture(fakeAgent);
  try {
    let result = await f.request("/api/chat", { message: "add something" });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.model.dirty, true);
    assert.doesNotMatch(readFileSync(f.doc, "utf8"), /Assistant change/);

    result = await f.request("/api/act", { action: "add", title: "Direct edit" });
    assert.equal(result.response.status, 409);
    assert.equal(result.body.code, "DRAFT_PENDING");

    writeFileSync(f.doc, FILE.replace("Existing", "External conflict"), "utf8");
    result = await f.request("/api/apply", {});
    assert.equal(result.response.status, 409);
    assert.equal(result.body.code, "VAULT_CONFLICT");
    assert.doesNotMatch(readFileSync(f.doc, "utf8"), /Assistant change/);

    result = await f.request("/api/reload", {});
    assert.equal(result.response.status, 200);
    assert.equal(result.body.model.urgent[0].title, "External conflict");
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("Auto routing picks model + turn budget per message; manual pick overrides", async () => {
  const seen = [];
  const fakeAgent = async (args) => {
    seen.push({ llmModel: args.llmModel, maxTurns: args.maxTurns, fallbackModel: args.fallbackModel, effort: args.effort });
    return { reply: "ok", sessionId: "s" };
  };
  const f = await fixture(fakeAgent);
  const last = () => seen.at(-1);
  try {
    // Trivial single-item edit → Haiku, tight turn budget, Sonnet fallback, no effort.
    await f.request("/api/chat", { message: "delete the milk todo" });
    assert.equal(last().llmModel, "haiku");
    assert.equal(last().maxTurns, 8);
    assert.equal(last().fallbackModel, "sonnet");
    assert.equal(last().effort, undefined);

    // Weekly-review intent from the button → Opus, full turns, high effort, no fallback.
    await f.request("/api/chat", { message: "let's review my week", intent: "review" });
    assert.equal(last().llmModel, "opus");
    assert.equal(last().maxTurns, 24);
    assert.equal(last().effort, "high");
    assert.equal(last().fallbackModel, undefined);

    // A pinned single todo (💬 bar) with a short instruction → Haiku.
    await f.request("/api/chat", { message: "get rid of it", context: { id: "i1", title: "X", bucket: "normal" } });
    assert.equal(last().llmModel, "haiku");

    // A manual pick in the picker overrides the router entirely.
    await f.request("/api/chat", { message: "delete the milk todo", model: "opus" });
    assert.equal(last().llmModel, "opus");

    // Uncertain / conversational → Sonnet (the safe default).
    await f.request("/api/chat", { message: "what should I focus on this afternoon?" });
    assert.equal(last().llmModel, "sonnet");
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("capture adds to Urgent and reports a near-duplicate", async () => {
  const f = await fixture();
  try {
    let r = await f.request("/api/capture", { title: "Brand new capture" });
    assert.equal(r.body.captured, true);
    assert.equal(r.body.bucket, "urgent");
    assert.equal(r.body.duplicateOf, null);
    assert.match(readFileSync(f.doc, "utf8"), /Brand new capture/);

    // The seed file has "Existing" in Urgent — a near-dup should be flagged (still captured).
    r = await f.request("/api/capture", { title: "existing" });
    assert.equal(r.body.captured, true);
    assert.equal(r.body.duplicateOf, "Existing");
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("adding a bare URL to To Read unfurls it to a titled link", async () => {
  const f = await fixture();
  try {
    // Point To Read at a tiny local server that returns an HTML title.
    const { createServer } = await import("node:http");
    const page = createServer((req, res) => { res.writeHead(200, { "content-type": "text/html" }); res.end("<title>Example Domain</title>"); });
    await new Promise((r) => page.listen(0, "127.0.0.1", r));
    const url = `http://127.0.0.1:${page.address().port}/`;
    const r = await f.request("/api/act", { action: "addToRead", text: url });
    assert.equal(r.response.status, 200);
    assert.match(readFileSync(f.doc, "utf8"), new RegExp(`\\[Example Domain\\]\\(${url.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}\\)`));
    await new Promise((res) => page.close(res));
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("unconfigured server can create and connect a blank Markdown file", async () => {
  const dir = mkdtempSync(join(tmpdir(), "bigrocks-setup-"));
  const doc = join(dir, "new.md");
  const server = createBigRocksServer({ initialTodoDocPath: undefined });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    let response = await fetch(base + "/api/model");
    let body = await response.json();
    assert.equal(body.configured, false);
    response = await fetch(base + "/api/config", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ path: doc, mode: "blank" }),
    });
    body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.model.configured, true);
    assert.match(readFileSync(doc, "utf8"), /## 🎯 Goals/);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    rmSync(dir, { recursive: true, force: true });
  }
});

test("undo reverts the last saved change and reports canUndo", async () => {
  const f = await fixture();
  try {
    // A fresh file has no history yet, so there is nothing to undo.
    let result = await f.request("/api/model");
    assert.equal(result.body.canUndo, false);
    result = await f.request("/api/undo", {});
    assert.equal(result.response.status, 400);

    // A direct edit snapshots the prior file, so undo becomes available.
    result = await f.request("/api/act", { action: "add", title: "Via API", bucket: "normal" });
    assert.equal(result.body.model.canUndo, true);
    assert.match(readFileSync(f.doc, "utf8"), /Via API/);

    // Undo restores the pre-edit file and pops that snapshot.
    result = await f.request("/api/undo", {});
    assert.equal(result.response.status, 200);
    assert.doesNotMatch(readFileSync(f.doc, "utf8"), /Via API/);
    assert.equal(result.body.model.urgent[0].title, "Existing");
    assert.equal(result.body.model.canUndo, false);

    // Nothing left to undo.
    result = await f.request("/api/undo", {});
    assert.equal(result.response.status, 400);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("a goals-changing draft reports before/after in the model view", async () => {
  // A big goals rewrite is "large", so it's held for review (before/after shown).
  const newGoals = ["**Launch**", "- Ship v2", "- Ship v3", "- Plan", "**Ops**", "- Hire", "- Onboard", "- Review"];
  const goalsAgent = async ({ model, ops }) => {
    model.goals = { headerLine: "## 🎯 Goals", rawLines: newGoals };
    ops.push("edited the Goals notepad");
    return { reply: "Reworked your goals.", sessionId: "test" };
  };
  const f = await fixture(goalsAgent);
  try {
    const result = await f.request("/api/chat", { message: "clean up my goals" });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.model.goalsChanged, true);
    assert.deepEqual(result.body.model.goalsBefore, []);
    assert.deepEqual(result.body.model.goals, newGoals);
    // Un-applied draft: the file on disk is untouched.
    assert.doesNotMatch(readFileSync(f.doc, "utf8"), /Ship v2/);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("chat streams the agent's steps over SSE when requested", async () => {
  const streamingAgent = async ({ model, ops, onEvent }) => {
    onEvent?.({ kind: "tool", label: "Reviewing your list" });
    onEvent?.({ kind: "text", text: "On it." });
    model.normal.push({ id: "x", title: "Streamed add", checked: false, starred: false });
    ops.push("added via stream");
    return { reply: "On it.", sessionId: "s1" };
  };
  const f = await fixture(streamingAgent);
  try {
    const res = await fetch(`http://127.0.0.1:${f.server.address().port}/api/chat`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "text/event-stream" },
      body: JSON.stringify({ message: "add something" }),
    });
    assert.equal(res.status, 200);
    assert.match(res.headers.get("content-type"), /text\/event-stream/);
    const body = await res.text();
    assert.match(body, /event: step/);
    assert.match(body, /Reviewing your list/);
    assert.match(body, /event: done/);
    assert.match(body, /Streamed add/); // final model rides in the done event
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("notes/create makes a new note directly and refuses duplicates", async () => {
  const f = await fixture();
  try {
    let r = await f.request("/api/notes/create", { name: "Ideas" });
    assert.equal(r.body.ok, true);
    assert.equal(r.body.path, "Ideas.md");
    assert.ok(existsSync(join(f.dir, "Ideas.md")));
    r = await f.request("/api/notes/create", { name: "Ideas" });
    assert.equal(r.response.status, 400); // already exists
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("a staged note edit is held for review, then written on Apply", async () => {
  const noteAgent = async ({ noteEdits }) => {
    noteEdits.push({ op: "create", name: "Meeting Notes", content: "# Meeting\n- takeaway", label: 'Create note "Meeting Notes"' });
    return { reply: "Drafted a note.", sessionId: "s" };
  };
  const f = await fixture(noteAgent);
  try {
    let r = await f.request("/api/chat", { message: "make a note" });
    assert.equal(r.body.model.dirty, true); // held, never auto-applied
    assert.equal(r.body.model.changes.length, 1);
    assert.equal(r.body.model.changes[0].kind, "note");
    assert.ok(!existsSync(join(f.dir, "Meeting Notes.md")), "nothing written before Apply");
    r = await f.request("/api/apply", {});
    assert.match(readFileSync(join(f.dir, "Meeting Notes.md"), "utf8"), /takeaway/);
    assert.equal(r.body.model.dirty, false);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("rejecting a staged note edit drops it with nothing written", async () => {
  const noteAgent = async ({ noteEdits }) => {
    noteEdits.push({ op: "create", name: "Scratchpad", content: "y", label: 'Create note "Scratchpad"' });
    return { reply: "ok", sessionId: "s" };
  };
  const f = await fixture(noteAgent);
  try {
    let r = await f.request("/api/chat", { message: "note" });
    assert.equal(r.body.model.changes.length, 1);
    r = await f.request("/api/reject-change", { key: r.body.model.changes[0].key });
    assert.equal(r.body.model.dirty, false);
    assert.ok(!existsSync(join(f.dir, "Scratchpad.md")));
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("a small change set applies directly (no draft) and reports what to flash", async () => {
  const oneAdd = async ({ model, ops }) => {
    model.normal.push({ id: "s1", title: "Quick add", checked: false, starred: false });
    ops.push("added Quick add");
    return { reply: "Done.", sessionId: "s" };
  };
  const f = await fixture(oneAdd);
  try {
    const r = await f.request("/api/chat", { message: "add one" });
    assert.equal(r.body.applied, true);
    assert.equal(r.body.model.dirty, false); // applied straight away, nothing pending
    assert.ok(r.body.flash.items.length >= 1); // UI has something to flash
    assert.match(readFileSync(f.doc, "utf8"), /Quick add/); // written to the file
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("individual proposed changes can be rejected, keeping the rest", async () => {
  const fourAdds = async ({ model, ops }) => {
    for (const t of ["Alpha", "Beta", "Gamma", "Delta"]) {
      model.normal.push({ id: "n-" + t, title: t, checked: false, starred: false });
      ops.push("added " + t);
    }
    return { reply: "Added four.", sessionId: "s" };
  };
  const f = await fixture(fourAdds);
  try {
    let r = await f.request("/api/chat", { message: "add four" });
    assert.equal(r.body.model.changes.length, 4); // large set → held for review
    const beta = r.body.model.changes.find((c) => c.label.includes("Beta"));
    r = await f.request("/api/reject-change", { key: beta.key });
    assert.equal(r.response.status, 200);
    assert.equal(r.body.model.changes.length, 3);
    r = await f.request("/api/apply", {});
    assert.match(readFileSync(f.doc, "utf8"), /Alpha/);
    assert.doesNotMatch(readFileSync(f.doc, "utf8"), /Beta/);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("approving one change applies just it and leaves the rest pending", async () => {
  const fourAdds = async ({ model, ops }) => {
    for (const t of ["Keep me", "Later one", "Third", "Fourth"]) {
      model.normal.push({ id: "a-" + t, title: t, checked: false, starred: false });
      ops.push("added " + t);
    }
    return { reply: "Added four.", sessionId: "s" };
  };
  const f = await fixture(fourAdds);
  try {
    let r = await f.request("/api/chat", { message: "add four" });
    const keep = r.body.model.changes.find((c) => c.label.includes("Keep me"));
    r = await f.request("/api/approve-change", { key: keep.key });
    assert.equal(r.response.status, 200);
    // Approved one is written to the file now; the others stay pending.
    assert.match(readFileSync(f.doc, "utf8"), /Keep me/);
    assert.doesNotMatch(readFileSync(f.doc, "utf8"), /Later one/);
    assert.equal(r.body.model.dirty, true);
    assert.equal(r.body.model.changes.length, 3);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("rejecting the only change drops the draft", async () => {
  // A big goals rewrite is one change but "large", so it's held for review.
  const goalsRewrite = async ({ model, ops }) => {
    model.goals = { headerLine: "## 🎯 Goals", rawLines: ["**A**", "- one", "- two", "- three", "**B**", "- four", "- five", "- six", "- seven"] };
    ops.push("rewrote goals");
    return { reply: "Reorganized.", sessionId: "s" };
  };
  const f = await fixture(goalsRewrite);
  try {
    let r = await f.request("/api/chat", { message: "reorg goals" });
    assert.equal(r.body.model.dirty, true);
    assert.equal(r.body.model.changes.length, 1);
    r = await f.request("/api/reject-change", { key: r.body.model.changes[0].key });
    assert.equal(r.body.model.dirty, false);
    assert.equal(r.body.model.changes.length, 0);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("documents attach to the vault, serve back, and remove to trash", async () => {
  const f = await fixture();
  try {
    const data = Buffer.from("hello doc").toString("base64");
    let r = await f.request("/api/documents", { name: "note.txt", data });
    assert.equal(r.response.status, 200);
    assert.equal(r.body.model.documents[0].name, "note.txt");
    assert.match(readFileSync(join(f.dir, "attachments", "note.txt"), "utf8"), /hello doc/);

    const fileRes = await fetch(`http://127.0.0.1:${f.server.address().port}/api/documents/file?name=note.txt`);
    assert.equal(fileRes.status, 200);
    assert.equal(await fileRes.text(), "hello doc");

    r = await f.request("/api/documents/remove", { name: "note.txt" });
    assert.equal(r.body.model.documents.length, 0);
    assert.ok(!existsSync(join(f.dir, "attachments", "note.txt")));
    // recoverable in the machine trash, not hard-deleted
    assert.ok(existsSync(join(f.dir, ".bigrocks", "trash")));
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("a duplicate document name is kept, not clobbered", async () => {
  const f = await fixture();
  try {
    const a = await f.request("/api/documents", { name: "d.txt", data: Buffer.from("one").toString("base64") });
    const b = await f.request("/api/documents", { name: "d.txt", data: Buffer.from("two").toString("base64") });
    assert.equal(a.body.name, "d.txt");
    assert.equal(b.body.name, "d (2).txt");
    assert.equal(b.body.model.documents.length, 2);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("Empty Trash permanently clears the Deleted bucket", async () => {
  const f = await fixture();
  try {
    // Move the seed item to Deleted, then empty the trash.
    let r = await f.request("/api/model");
    const id = r.body.urgent[0].id;
    await f.request("/api/act", { action: "delete", id });
    r = await f.request("/api/model");
    assert.equal(r.body.deleted.length, 1);
    r = await f.request("/api/act", { action: "clearDeleted" });
    assert.equal(r.body.model.deleted.length, 0);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("native picker endpoint uses the chosen path and requested creation mode", async () => {
  const dir = mkdtempSync(join(tmpdir(), "bigrocks-picker-"));
  const doc = join(dir, "picked.md");
  const calls = [];
  const server = createBigRocksServer({
    initialTodoDocPath: undefined,
    filePicker: async (mode) => { calls.push(mode); return doc; },
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const response = await fetch(base + "/api/pick-file", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ mode: "demo" }),
    });
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.deepEqual(calls, ["demo"]);
    assert.equal(body.model.todoDocPath, doc);
    assert.match(readFileSync(doc, "utf8"), /Review launch blockers/);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    rmSync(dir, { recursive: true, force: true });
  }
});

test("HTTP: assistant-staged vault cleanup — review rows, apply moves/trashes, then undo", async () => {
  // A stub agent that stages a move and a trash exactly as the real tools do.
  const stub = async ({ cleanup, noteEdits }) => {
    const mv = cleanup.stageMove({ path: "Loose.md", to_folder: "Filed", reason: "belongs in Filed" });
    if (mv.intent) noteEdits.push(mv.intent);
    const tr = cleanup.stageTrash({ path: "Junk.md", reason: "empty scrap" });
    if (tr.intent) noteEdits.push(tr.intent);
    return { reply: "Proposed a move and a trash.", sessionId: "s" };
  };
  const f = await fixture(stub);
  try {
    writeFileSync(join(f.dir, "Loose.md"), "# Loose\n\ncontent\n");
    writeFileSync(join(f.dir, "Junk.md"), "   \n");

    let { body } = await f.request("/api/chat", { message: "tidy up" });
    assert.equal(body.applied, false, "note-touching drafts never auto-apply");
    assert.equal(body.model.dirty, true);
    assert.deepEqual(body.model.changes.map((c) => c.kind).sort(), ["note-move", "note-trash"]);

    ({ body } = await f.request("/api/apply", {}));
    assert.ok(existsSync(join(f.dir, "Filed", "Loose.md")) && !existsSync(join(f.dir, "Loose.md")), "note moved");
    assert.ok(!existsSync(join(f.dir, "Junk.md")), "note trashed");
    assert.equal(body.model.canUndoCleanup, true);
    assert.equal(body.model.dirty, false);

    ({ body } = await f.request("/api/cleanup/undo", {}));
    assert.equal(body.done, true);
    assert.equal(body.restored, 2);
    assert.ok(existsSync(join(f.dir, "Loose.md")) && !existsSync(join(f.dir, "Filed", "Loose.md")), "move undone");
    assert.ok(existsSync(join(f.dir, "Junk.md")), "trash undone");
    assert.equal(body.model.canUndoCleanup, false);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("HTTP: a cleanup op whose file changed on disk is skipped and kept in the panel", async () => {
  const stub = async ({ cleanup, noteEdits }) => {
    const mv = cleanup.stageMove({ path: "Moves.md", to_folder: "Filed", reason: "x" });
    if (mv.intent) noteEdits.push(mv.intent);
    return { reply: "staged", sessionId: "s" };
  };
  const f = await fixture(stub);
  try {
    writeFileSync(join(f.dir, "Moves.md"), "original\n");
    await f.request("/api/chat", { message: "move it" });
    writeFileSync(join(f.dir, "Moves.md"), "EDITED since staging\n"); // change under the plan
    const { body } = await f.request("/api/apply", {});
    assert.ok((body.notes || []).some((n) => n.skipped), "reported as skipped");
    assert.ok(existsSync(join(f.dir, "Moves.md")) && !existsSync(join(f.dir, "Filed", "Moves.md")), "not moved");
    assert.equal(body.model.dirty, true, "skipped op kept in the panel");
    assert.deepEqual(body.model.changes.map((c) => c.kind), ["note-move"]);
  } finally {
    await new Promise((resolve) => f.server.close(resolve));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("HTTP: completing a linked todo appends to the note's ## Log", async () => {
  const f = await fixture();
  try {
    writeFileSync(join(f.dir, "Sergey.md"), "# Sergey\n\n## Log\n\n- 2026-07-01 ✓ intro\n", "utf8");
    let { body } = await f.request("/api/act", { action: "add", title: "Ping Sergey [[Sergey]]", bucket: "urgent" });
    const item = body.model.urgent.find((it) => it.title.includes("Ping Sergey"));
    assert.ok(item, "todo added");
    assert.deepEqual(item.links, ["Sergey"], "itemView carries links");
    ({ body } = await f.request("/api/act", { action: "complete", id: item.id }));
    assert.deepEqual(body.activity?.logged, ["Sergey"], "logged to the opted-in note");
    assert.match(readFileSync(join(f.dir, "Sergey.md"), "utf8"), /intro[\s\S]*✓ Ping Sergey/);
  } finally {
    await new Promise((r) => f.server.close(r));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("HTTP: a linked note with no ## Log is suggested, then enable + undo work", async () => {
  const f = await fixture();
  try {
    writeFileSync(join(f.dir, "Krystina.md"), "# Krystina\n\nNotes.\n", "utf8");
    let { body } = await f.request("/api/act", { action: "add", title: "Sync with Krystina [[Krystina]]", bucket: "urgent" });
    const item = body.model.urgent.find((it) => it.title.includes("Krystina"));
    ({ body } = await f.request("/api/act", { action: "complete", id: item.id }));
    assert.equal((body.activity?.logged || []).length, 0, "nothing auto-logged");
    assert.deepEqual((body.activity?.suggest || []).map((s) => s.note), ["Krystina"], "suggested");
    assert.ok(!/## Log/.test(readFileSync(join(f.dir, "Krystina.md"), "utf8")), "not written until enabled");
    const suggest = body.activity.suggest;
    ({ body } = await f.request("/api/activity/enable", { items: suggest }));
    assert.deepEqual(body.logged, ["Krystina"]);
    assert.match(readFileSync(join(f.dir, "Krystina.md"), "utf8"), /## Log[\s\S]*✓ Sync with Krystina/);
    ({ body } = await f.request("/api/activity/undo", {}));
    assert.equal(body.removed, 1);
    assert.ok(!/Sync with Krystina/.test(readFileSync(join(f.dir, "Krystina.md"), "utf8")), "undo removed the line");
  } finally {
    await new Promise((r) => f.server.close(r));
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test("HTTP: completing a todo while the assistant is working does not reopen it", async () => {
  let f;
  const stub = async ({ model, ops }) => {
    // Mid-chat, a direct edit lands (the user checks a todo off) …
    const before = await f.request("/api/model");
    const existing = before.body.urgent.find((it) => it.title === "Existing");
    await f.request("/api/act", { action: "complete", id: existing.id });
    // … and the agent also adds one to its (now-stale) candidate.
    model.urgent.push({ id: "iAgentAdded", title: "Agent added this", checked: false, starred: false });
    ops.push("added Agent added this");
    return { reply: "worked on it", sessionId: "s" };
  };
  f = await fixture(stub);
  try {
    const { body } = await f.request("/api/chat", { message: "do something" });
    const titles = (b) => (b || []).map((it) => it.title);
    assert.ok(!titles(body.model.urgent).includes("Existing"), "the checked-off todo is NOT back in Urgent");
    assert.ok(titles(body.model.completed).includes("Existing"), "it stayed completed");
    assert.ok(titles(body.model.urgent).includes("Agent added this"), "the assistant's own change still applied");
  } finally {
    await new Promise((r) => f.server.close(r));
    rmSync(f.dir, { recursive: true, force: true });
  }
});
