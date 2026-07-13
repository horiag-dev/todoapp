import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { findById, reflowUrgent, newItem, itemView } from "./model.mjs";
import { tagsOf } from "./parse.mjs";
import { ageDays } from "./ledger.mjs";
import { insertGoal } from "./ops.mjs";

const ok = (text) => ({ content: [{ type: "text", text }] });

const SYSTEM = `You are the assistant inside "Big Rocks First", a todo app backed by a single markdown file the user owns.

The model is categorical, never temporal — there are NO due dates, calendars, or recurring tasks. Never invent or ask for dates.
- Goals: a long-term notepad. Move a task here (move_to_goals) when it's really a goal/theme, not an action. You can also read and rewrite the whole notepad (read_goals → write_goals) to reorganize, tidy, or add/remove goal lines under **Subsection** headers.
- Urgent: the active working list. An item can be marked "Today" (very urgent) — Today items float to the top.
- Normal: the pile of everything else.
- Top 5: the handful of priorities for the week.
- Documents: files the user has attached, kept in the vault. Use list_documents to see them and read_document to read one when the user refers to a file, or asks you to summarize, use, or pull from it.

You work on a DRAFT. Make the changes the user asks for using the tools; the user reviews the pending changes and clicks Apply, so you don't need to ask permission for ordinary edits — just do them, then give a ONE-LINE summary of what you changed. For clearly destructive or bulk actions (deleting several items, clearing a whole section), state plainly what you're about to do and do it, but keep it easy to undo by describing it.

Reference items by their id. Default new captures to Urgent. Use tags (#like_this) to organize the Normal pile when asked.

Items and To Read entries carry age_days — how many days they've sat untouched. When asked to tidy, de-stale, or clean up, use it: propose removing old, low-value To Read links (and stale items), and always name exactly what you're removing so it's easy to review before Apply. Be concise and act rather than over-explaining.`;

function buildServer(ctx) {
  const { model, ops, seen, docs } = ctx;
  const need = (id) => {
    const f = findById(model, id);
    if (!f) throw new Error(`No item with id ${id}`);
    return f;
  };
  const move = (f, to) => {
    f.arr.splice(f.idx, 1);
    model[to].push(f.item);
  };

  const tools = [
    tool("list_items", "List items in a bucket (includes age_days).", { bucket: z.enum(["urgent", "normal", "top5", "completed", "deleted", "toread"]) }, async ({ bucket }) => {
      if (bucket === "toread") {
        return ok(JSON.stringify((model.toread?.rawLines ?? []).map((l) => {
          const t = l.replace(/^-\s+/, "").trim();
          return { text: t, age_days: ageDays(seen, t) };
        })));
      }
      const arr = model[bucket] ?? [];
      const cap = bucket === "completed" || bucket === "deleted" ? arr.slice(-40) : arr;
      return ok(JSON.stringify(cap.map((it) => ({ ...itemView(it), age_days: ageDays(seen, it.title) }))));
    }),
    tool("read_goals", "Read the Goals notepad (raw markdown).", {}, async () => ok(model.goals?.rawLines?.join("\n") ?? "")),
    tool("write_goals", "Rewrite the Goals notepad with new markdown content. ALWAYS read_goals first and preserve everything you are not intentionally changing — this replaces the whole notepad. Use **Subsection** bold headers and `- ` bullets, like the existing content.", { content: z.string() }, async ({ content }) => {
      if (!model.goals) model.goals = { headerLine: "## 🎯 Goals", rawLines: [] };
      model.goals.rawLines = content.replace(/\r/g, "").split("\n");
      ops.push("edited the Goals notepad");
      return ok("Goals updated.");
    }),
    tool("search", "Search item titles across Urgent, Normal, and Top 5.", { query: z.string() }, async ({ query }) => {
      const q = query.toLowerCase();
      const hits = ["urgent", "normal", "top5"].flatMap((b) =>
        model[b].filter((it) => it.title.toLowerCase().includes(q)).map((it) => ({ ...itemView(it), bucket: b })),
      );
      return ok(JSON.stringify(hits));
    }),
    tool("add_todo", "Add a new todo. First check the board/list_items: if an item with essentially the same meaning already exists, don't duplicate it — tell the user about the existing one (or refine it) instead of adding.", { title: z.string(), bucket: z.enum(["urgent", "normal"]).optional(), today: z.boolean().optional() }, async ({ title, bucket = "urgent", today = false }) => {
      const b = today ? "urgent" : bucket;
      const it = newItem(title, { starred: today });
      model[b].push(it);
      if (b === "urgent") reflowUrgent(model);
      ops.push(`added "${title}" to ${b}${today ? " · Today" : ""}`);
      return ok(`Added ${it.id}.`);
    }),
    tool("set_priority", "Move an item between Urgent and Normal.", { id: z.string(), bucket: z.enum(["urgent", "normal"]) }, async ({ id, bucket }) => {
      const f = need(id);
      if (f.bucket !== bucket) { move(f, bucket); if (bucket === "urgent") reflowUrgent(model); }
      ops.push(`moved "${f.item.title}" to ${bucket}`);
      return ok("Moved.");
    }),
    tool("set_today", "Mark an item as Today (very urgent); moves it into Urgent if needed.", { id: z.string() }, async ({ id }) => {
      const f = need(id);
      if (f.bucket !== "urgent") move(f, "urgent");
      f.item.starred = true; reflowUrgent(model);
      ops.push(`marked "${f.item.title}" as Today`);
      return ok("Marked Today.");
    }),
    tool("clear_today", "Remove the Today mark from an item.", { id: z.string() }, async ({ id }) => {
      const f = need(id); f.item.starred = false; reflowUrgent(model);
      ops.push(`cleared Today on "${f.item.title}"`);
      return ok("Cleared.");
    }),
    tool("move_to_goals", "Move an item into the Goals notepad (optionally under a **subsection**).", { id: z.string(), subsection: z.string().optional() }, async ({ id, subsection }) => {
      const f = need(id);
      insertGoal(model, f.item.title, subsection);
      f.arr.splice(f.idx, 1);
      ops.push(`moved "${f.item.title}" to Goals${subsection ? ` (${subsection})` : ""}`);
      return ok("Moved to Goals.");
    }),
    tool("add_to_top5", "Add a title to this week's Top 5.", { title: z.string() }, async ({ title }) => {
      model.top5.push(newItem(title));
      ops.push(`added "${title}" to Top 5`);
      return ok("Added to Top 5.");
    }),
    tool("add_to_read", "Add a link or reference to the To Read list.", { url: z.string() }, async ({ url }) => {
      if (!model.toread) model.toread = { headerLine: "## 📚 To Read", rawLines: [] };
      model.toread.rawLines.push(`- ${url}`);
      ops.push(`added to To Read: ${url}`);
      return ok("Added to To Read.");
    }),
    tool("remove_from_read", "Remove a To Read entry containing the given text (use for de-staling).", { match: z.string() }, async ({ match }) => {
      const lines = model.toread?.rawLines ?? [];
      const i = lines.findIndex((l) => l.toLowerCase().includes(match.toLowerCase()));
      if (i === -1) return ok(`No To Read entry matching "${match}".`);
      const [removed] = lines.splice(i, 1);
      ops.push(`removed from To Read: ${removed.replace(/^-\s+/, "").trim()}`);
      return ok("Removed from To Read.");
    }),
    tool("complete", "Mark an item done (moves it to Completed).", { id: z.string() }, async ({ id }) => {
      const f = need(id); f.item.checked = true; move(f, "completed");
      ops.push(`completed "${f.item.title}"`);
      return ok("Completed.");
    }),
    tool("edit_title", "Change an item's title.", { id: z.string(), title: z.string() }, async ({ id, title }) => {
      const f = need(id); const old = f.item.title; f.item.title = title;
      ops.push(`renamed "${old}" → "${title}"`);
      return ok("Renamed.");
    }),
    tool("delete", "Delete an item (recoverable — moves to Deleted).", { id: z.string() }, async ({ id }) => {
      const f = need(id); f.item.checked = true; move(f, "deleted");
      ops.push(`deleted "${f.item.title}"`);
      return ok("Deleted.");
    }),
    tool("list_documents", "List the documents the user has attached (files in the vault's attachments folder).", {}, async () => {
      const list = docs?.list?.() ?? [];
      return ok(list.length ? JSON.stringify(list.map((d) => ({ name: d.name, size: d.size }))) : "No documents are attached.");
    }),
    tool("read_document", "Read the text contents of an attached document by exact name. Works for text files (markdown, txt, csv, json, code, etc.). Binary files like PDFs or images cannot be read as text yet.", { name: z.string() }, async ({ name }) => {
      const buf = docs?.read?.(name);
      if (!buf) return ok(`No document named "${name}". Use list_documents to see what's attached.`);
      if (buf.subarray(0, 8000).includes(0)) return ok(`"${name}" looks like a binary file (PDF, image, or Office doc); I can't read it as text yet.`);
      const LIMIT = 40000;
      const text = buf.toString("utf8");
      return ok(text.length > LIMIT ? `${text.slice(0, LIMIT)}\n\n…[truncated; ${buf.length} bytes total]` : text);
    }),
  ];

  return createSdkMcpServer({ name: "todo", version: "0.1.0", tools });
}

function snapshot(model, docs) {
  const u = model.urgent.map((it) => `  ${it.id}${it.starred ? " ·Today" : ""} — ${it.title}`).join("\n");
  const tags = [...new Set(model.normal.flatMap((it) => tagsOf(it.title)))];
  const subs = (model.goals?.rawLines ?? []).filter((l) => /^\*\*.+\*\*$/.test(l.trim())).map((l) => l.trim());
  const top5 = model.top5.map((it) => `  ${it.id} — ${it.title}`).join("\n");
  const documents = docs?.list?.() ?? [];
  return [
    `Urgent (${model.urgent.length}):`, u || "  (none)",
    `Normal: ${model.normal.length} items. Tags in use: ${tags.length ? tags.map((t) => "#" + t).join(" ") : "(none)"}`,
    `Top 5 (${model.top5.length}):`, top5 || "  (none)",
    `Goals subsections: ${subs.join(", ") || "(none)"}`,
    `To Read: ${model.toread?.rawLines?.length ?? 0} lines · Completed: ${model.completed.length} · Deleted: ${model.deleted.length}`,
    `Documents: ${documents.length ? documents.map((d) => d.name).join(", ") : "(none)"}`,
  ].join("\n");
}

const TOOL_NAMES = [
  "list_items", "read_goals", "search", "add_todo", "set_priority", "set_today",
  "clear_today", "move_to_goals", "add_to_top5", "complete", "edit_title", "delete",
].map((n) => `mcp__todo__${n}`);

// Friendly labels so the chat can narrate what the agent is doing, live.
const TOOL_LABELS = {
  list_items: "Reviewing your list", read_goals: "Reading your goals",
  write_goals: "Rewriting your goals", search: "Searching your todos",
  add_todo: "Adding a todo", set_priority: "Changing a priority",
  set_today: "Marking something Today", clear_today: "Clearing Today",
  move_to_goals: "Moving to Goals", add_to_top5: "Updating Top 5",
  add_to_read: "Adding to To Read", remove_from_read: "Pruning To Read",
  complete: "Completing an item", edit_title: "Editing an item", delete: "Deleting an item",
  list_documents: "Checking your documents", read_document: "Reading a document",
};
const toolLabel = (name) => {
  const bare = String(name || "").replace(/^mcp__todo__/, "");
  return TOOL_LABELS[bare] || bare.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase());
};

export async function runAgent({ model, ops, seen, message, sessionId, abortController, onEvent, docs }) {
  const emit = (event) => { try { onEvent?.(event); } catch {} };
  const server = buildServer({ model, ops, seen, docs });
  const prompt = `Current board:\n${snapshot(model, docs)}\n\nUser: ${message}`;

  let reply = "";
  let session = sessionId;
  const q = query({
    prompt,
    options: {
      systemPrompt: SYSTEM,
      settingSources: [],
      mcpServers: { todo: server },
      maxTurns: 24,
      ...(abortController ? { abortController } : {}),
      ...(sessionId ? { resume: sessionId } : {}),
      canUseTool: async (name) =>
        name.startsWith("mcp__todo__")
          ? { behavior: "allow", updatedInput: undefined }
          : { behavior: "deny", message: "Only the todo tools are available." },
    },
  });

  for await (const msg of q) {
    if (msg.session_id) session = msg.session_id;
    if (msg.type === "assistant") {
      let msgText = "";
      for (const b of msg.message?.content ?? []) {
        if (b.type === "text" && b.text) { msgText += b.text; emit({ kind: "text", text: b.text }); }
        else if (b.type === "thinking" && b.thinking) emit({ kind: "thinking", text: b.thinking });
        else if (b.type === "tool_use") emit({ kind: "tool", label: toolLabel(b.name) });
      }
      // Separate narration emitted across turns (text · tool · text) with a blank line.
      if (msgText.trim()) reply += (reply ? "\n\n" : "") + msgText;
    } else if (msg.type === "result" && msg.result && !reply) {
      reply = msg.result;
    }
  }
  return { reply: reply.trim(), sessionId: session };
}
