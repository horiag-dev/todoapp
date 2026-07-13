import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
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
  const fakeAgent = async ({ model, ops }) => {
    model.normal.push({ id: "fake", title: "Assistant change", checked: false, starred: false });
    ops.push("added assistant change");
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
