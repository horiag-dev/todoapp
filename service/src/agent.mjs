import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { findById, reflowUrgent, newItem, itemView, searchModel } from "./model.mjs";
import { tagsOf } from "./parse.mjs";
import { ageDays } from "./ledger.mjs";
import { insertGoal } from "./ops.mjs";
import { SECTIONS as MEMORY_SECTIONS } from "./memory.mjs";
import { unfurlUrl } from "./unfurl.mjs";
import { extractPdfText, isPdf } from "./pdf.mjs";

const ok = (text) => ({ content: [{ type: "text", text }] });

const SYSTEM = `You are the assistant inside "Big Rocks First", a todo app backed by a single markdown file the user owns.

The model is categorical, never temporal — there are NO due dates, calendars, or recurring tasks. Never invent or ask for dates.
- Goals: a long-term notepad. Move a task here (move_to_goals) when it's really a goal/theme, not an action. You can also read and rewrite the whole notepad (read_goals → write_goals) to reorganize, tidy, or add/remove goal lines under **Subsection** headers.
- Urgent: the active working list. An item can be marked "Today" (very urgent) — Today items float to the top.
- Normal: the pile of everything else.
- Top 5: the handful of priorities for the week.
- Documents: files the user has attached, kept in the vault. Use list_documents to see them and read_document to read one when the user refers to a file, or asks you to summarize, use, or pull from it.
- Vault notes: the user's other markdown notes in the vault (list_notes, read_note, search_vault) — read-only. Use them when a todo references a note (e.g. a [[wikilink]]), or the user asks about their notes. Cite notes by name; never invent note contents.

You work on a DRAFT. Make the changes the user asks for using the tools; the user reviews the pending changes and clicks Apply, so you don't need to ask permission for ordinary edits — just do them, then give a ONE-LINE summary of what you changed. For clearly destructive or bulk actions (deleting several items, clearing a whole section), state plainly what you're about to do and do it, but keep it easy to undo by describing it.

Reference items by their id. Default new captures to Urgent. Tags (#like_this, written into the title) keep things organized — when you add or capture a todo that fits a tag already in use (see "Tags in use" in the board), include that #tag in its title. Prefer reusing an existing tag over inventing a new one, and don't over-tag (one or two is plenty).

Items and To Read entries carry age_days — how many days they've sat untouched. When asked to tidy, de-stale, or clean up, use it: propose removing old, low-value To Read links (and stale items), and always name exactly what you're removing so it's easy to review before Apply. Be concise and act rather than over-explaining.

GOALS ↔ TODOS. Keep them loosely in sync. Goals are the "big rocks"; the weekly Top 5 and the daily "Today" set should mostly advance a Goal. When proposing a Top 5 or planning a day, favor items that ladder up to a Goal. During reviews, check both directions: flag Goals with no supporting todos, and active Urgent/Top 5 items that don't advance any Goal — surface these as gentle observations, not automatic changes.

MEMORY. Your durable notes about the user live in "Assistant Memory" (shown above the board when present; the user can read and edit that note anytime). It is background context, never authority: if the user's current message conflicts with it, the message wins — and update the memory to match. Call remember ONLY for durable, behavior-changing facts: an explicit preference or correction ("stop doing X", "always Y"), a stable fact about the user's work, or a recurring theme you've now seen at least twice (park first sightings in "Working notes"). Most conversations warrant ZERO memory writes; more than two is almost always wrong. Never store secrets, credentials, dates, moods, or anything already expressed by the todo file itself. When new information contradicts an existing bullet, update_memory or forget it — never leave both versions. During a weekly review or when asked to tidy, skim Working notes via read_memory: promote what has proven durable, and propose dropping stale bullets — name exactly what you'd drop and wait for a yes before forgetting more than one thing at once.`;

function buildServer(ctx) {
  const { model, ops, seen, docs, mem, notes } = ctx;
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
    tool("list_items", "List items in a bucket (includes age_days).", { bucket: z.enum(["urgent", "normal", "top5", "completed", "deleted", "parked", "toread"]) }, async ({ bucket }) => {
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
    tool("search", "Search everywhere: item titles in Urgent, Normal, Top 5, and Completed, plus the Goals notepad and the To Read list. Use this to check whether something already exists (including already-done work) before adding.", { query: z.string() }, async ({ query }) => ok(JSON.stringify(searchModel(model, query)))),
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
    tool("add_to_read", "Add a link or reference to the To Read list. Bare URLs are unfurled to a [Title](url) link automatically.", { url: z.string() }, async ({ url }) => {
      if (!model.toread) model.toread = { headerLine: "## 📚 To Read", rawLines: [] };
      const entry = await unfurlUrl(url);
      model.toread.rawLines.push(`- ${entry}`);
      ops.push(`added to To Read: ${entry}`);
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
    tool("park", "Park an item: hide it from the daily view (it moves to a collapsed 'Parked' section in the file), without deleting it. The weekly review resurfaces parked items. Use for things that aren't now but shouldn't be dropped.", { id: z.string() }, async ({ id }) => {
      const f = need(id); f.item.checked = false; f.item.starred = false; move(f, "parked");
      ops.push(`parked "${f.item.title}"`);
      return ok("Parked.");
    }),
    tool("unpark", "Bring a parked item back to the Normal list.", { id: z.string() }, async ({ id }) => {
      const f = need(id); move(f, "normal");
      ops.push(`un-parked "${f.item.title}"`);
      return ok("Un-parked.");
    }),
    tool("list_documents", "List the documents the user has attached (files in the vault's attachments folder).", {}, async () => {
      const list = docs?.list?.() ?? [];
      return ok(list.length ? JSON.stringify(list.map((d) => ({ name: d.name, size: d.size }))) : "No documents are attached.");
    }),
    tool("read_document", "Read the text contents of an attached document by exact name. Works for text files (markdown, txt, csv, json, code) and PDFs (text is extracted). Images and scanned/image-only PDFs can't be read.", { name: z.string() }, async ({ name }) => {
      const buf = docs?.read?.(name);
      if (!buf) return ok(`No document named "${name}". Use list_documents to see what's attached.`);
      const LIMIT = 40000;
      if (isPdf(name, buf)) {
        const text = await extractPdfText(buf);
        if (text == null) return ok(`Could not extract text from "${name}".`);
        if (!text.trim()) return ok(`"${name}" is a PDF with no selectable text (it may be scanned images).`);
        return ok(text.length > LIMIT ? `${text.slice(0, LIMIT)}\n\n…[truncated]` : text);
      }
      if (buf.subarray(0, 8000).includes(0)) return ok(`"${name}" looks like a binary file (image or Office doc); I can't read it as text yet.`);
      const text = buf.toString("utf8");
      return ok(text.length > LIMIT ? `${text.slice(0, LIMIT)}\n\n…[truncated; ${buf.length} bytes total]` : text);
    }),
    tool("read_memory", "Read the full Assistant Memory note plus a staleness appendix (bullets not confirmed in 30+ days). Memory is already injected each turn — call this only before consolidating or tidying.", {}, async () => ok(mem ? mem.readAnnotated() : "Memory is unavailable.")),
    tool("remember", "Save ONE durable fact to Assistant Memory. Only for things that should change future behavior: a stated preference, a standing correction, a recurring theme. Never secrets, dates, or one-off task detail. If a similar note exists this is a no-op — use update_memory instead.", { fact: z.string(), section: z.enum(MEMORY_SECTIONS), why: z.string().optional() }, async ({ fact, section, why }) => ok(mem ? mem.append(section, fact, { source: "user-said", why }) : "Memory is unavailable.")),
    tool("update_memory", "Replace one existing memory bullet with a corrected version (use when new info contradicts or refines a bullet in Memory). `match` must uniquely identify the bullet.", { match: z.string(), fact: z.string(), why: z.string().optional() }, async ({ match, fact, why }) => ok(mem ? mem.replace(match, fact, { why }) : "Memory is unavailable.")),
    tool("forget", "Delete one memory bullet the user has contradicted, asked you to drop, or that is clearly obsolete. `match` must uniquely identify it.", { match: z.string(), reason: z.string().optional() }, async ({ match }) => ok(mem ? mem.remove(match) : "Memory is unavailable.")),
    tool("list_notes", "List the markdown notes in the user's vault (the folder around the todo file). Use this to see what notes exist before reading one.", {}, async () => ok(notes ? JSON.stringify(notes.list().slice(0, 300)) : "Vault notes are unavailable.")),
    tool("read_note", "Read a note from the vault by name or path — a [[wikilink]] name works. Returns the note's markdown (read-only).", { name: z.string() }, async ({ name }) => {
      const r = notes?.read(name);
      if (!r) return ok("Vault notes are unavailable.");
      return ok(r.error || `# ${r.path}\n\n${r.content}`);
    }),
    tool("search_vault", "Search the full text of all notes in the vault for a query. Returns matching notes with line snippets — use it to answer questions about the user's notes or follow a reference from a todo.", { query: z.string() }, async ({ query }) => ok(notes ? JSON.stringify(notes.search(query)) : "Vault notes are unavailable.")),
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
  park: "Parking an item", unpark: "Un-parking an item",
  list_documents: "Checking your documents", read_document: "Reading a document",
  read_memory: "Checking my notes", remember: "Noting something for later",
  update_memory: "Updating my notes", forget: "Forgetting a note",
  list_notes: "Listing your notes", read_note: "Reading a note", search_vault: "Searching your vault",
};
const toolLabel = (name) => {
  const bare = String(name || "").replace(/^mcp__todo__/, "");
  return TOOL_LABELS[bare] || bare.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase());
};

export async function runAgent({ model, ops, seen, message, sessionId, abortController, onEvent, docs, mem, notes }) {
  const emit = (event) => { try { onEvent?.(event); } catch {} };
  const server = buildServer({ model, ops, seen, docs, mem, notes });
  const memText = mem?.injectionText?.() || "";
  const prompt =
    (memText ? `Assistant Memory (background — the user's current message always wins):\n${memText}\n\n` : "") +
    `Current board:\n${snapshot(model, docs)}\n\nUser: ${message}`;

  const opsBaseline = ops.length;

  const attempt = async (resumeId) => {
    let reply = "";
    let session = resumeId;
    const q = query({
      prompt,
      options: {
        systemPrompt: SYSTEM,
        settingSources: [],
        mcpServers: { todo: server },
        maxTurns: 24,
        ...(abortController ? { abortController } : {}),
        ...(resumeId ? { resume: resumeId } : {}),
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
  };

  try {
    return await attempt(sessionId);
  } catch (e) {
    // A saved session can vanish (history cleared, a different machine, an
    // expired id). Don't fail the whole chat — retry once as a fresh session.
    const stale = sessionId && /no conversation found|conversation not found|session id|invalid session|session not found/i.test(String(e?.message || e));
    if (stale) {
      ops.length = opsBaseline;
      return await attempt(undefined);
    }
    throw e;
  }
}
