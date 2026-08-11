import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { findById, reflowUrgent, newItem, itemView, searchModel, MUST_CAP, countMusts, blockerOf, releaseFollower, normalizeChains } from "./model.mjs";
import { tagsOf } from "./parse.mjs";
import { ageDays, mustDays } from "./ledger.mjs";
import { insertGoal } from "./ops.mjs";
import { SECTIONS as MEMORY_SECTIONS } from "./memory.mjs";
import { unfurlUrl } from "./unfurl.mjs";
import { extractPdfText, isPdf } from "./pdf.mjs";

const ok = (text) => ({ content: [{ type: "text", text }] });

// Every built-in tool the agent SDK would otherwise inject into the prompt. This
// app is MCP-tools-only, so all of them are dead weight — see disallowedTools below.
const BUILTIN_TOOLS = [
  "Bash", "BashOutput", "KillShell", "Read", "Write", "Edit", "MultiEdit", "NotebookEdit",
  "Glob", "Grep", "WebFetch", "WebSearch", "TodoWrite", "Task", "Agent", "Skill",
  "SlashCommand", "Workflow", "ToolSearch", "ListMcpResources", "ReadMcpResource",
  "ExitPlanMode", "EnterPlanMode", "AskUserQuestion", "Artifact", "Monitor",
  "CronCreate", "CronList", "CronDelete", "TaskCreate", "TaskGet", "TaskList",
  "TaskOutput", "TaskStop", "TaskUpdate", "SendMessage", "PushNotification",
  "RemoteTrigger", "ScheduleWakeup", "ReportFindings", "DesignSync", "EnterWorktree",
  "ExitWorktree", "EndConversation", "WebviewScreenshot",
];

// The prompt is assembled per request to match the loaded tool scope (see
// TOOL_GROUPS): a core run doesn't pay for the vault-cleanup, memory or
// activity-log sections it can't act on. CORE is what every run gets.
const CORE = `You are the assistant inside "Big Rocks First", a todo app backed by a single markdown file the user owns.

The model is categorical, never temporal — there are NO due dates, calendars, or recurring tasks. Never invent or ask for dates.
- Goals: a long-term notepad of the user's big rocks.
- Urgent: the active working list.
- Normal: the pile of everything else.
- Top 5: the handful of priorities for the week.

QUEUES. Items can be sequential: queue_after marks an item as waiting on the one directly ABOVE it in the same section (shown as ·after↑ in the board). A queue is just consecutive lines, so ordering IS the dependency — to queue B behind A, B must sit directly below A (reorder first if not). A queued item isn't startable: it can't be Today or Must, and marking it either releases it. Completing/deleting/parking the head automatically releases the next one. Use this only for real sequencing ("can't send invites before booking the venue"), never for things that are merely related — that's what tags are for.

THE COMMITMENT LADDER: Urgent (could do) → Today (intends to) → Must (has committed to). Both Today and Must live in Urgent and float to the top, Must above Today.
- "Today" is an intention — what the user would LIKE to get done. Generous; no cap.
- "Must" is a commitment — non-negotiable, there are consequences if it slips. Hard cap of ${MUST_CAP}, and the cap is the point: it's what stops Must from silently becoming a second Today. A Must is always also a Today.
- Promote to Must only from Today, and only when the user's own words make it non-negotiable ("I have to", "this can't slip", "hard deadline"). Wanting something a lot is not a Must. When in doubt, mark it Today and say so.
- If the user asks for a fourth Must, DON'T silently drop one — name the three current Musts and ask which one is no longer a must.
- Musts never expire on their own and never roll over automatically. There's no midnight, only the next time the user plans their day.
- Each Must carries must_days — how many days it has been a Must. If one has been a Must for 3+ days, say so ONCE, plainly: it's either genuinely stuck or it was never really a must, and ask which. Don't nag about the same item twice in a conversation.

You work on a DRAFT. Make the changes the user asks for using the tools; the user reviews the pending changes and clicks Apply, so you don't need to ask permission for ordinary edits — just do them, then give a ONE-LINE summary of what you changed. For clearly destructive or bulk actions (deleting several items, clearing a whole section), state plainly what you're about to do and do it, but keep it easy to undo by describing it.

Reference items by their id. You keep the recent conversation, and ids are stable within it — so when the user refers to something you just listed or discussed ("delete it", "that one", "move the second"), act on the id you already have. Don't search again for an item you just showed them. Default new captures to Urgent. Tags (#like_this, written into the title) keep things organized — when you add or capture a todo that fits a tag already in use (see "Tags in use" in the board), include that #tag in its title. Prefer reusing an existing tag over inventing a new one, and don't over-tag (one or two is plenty).

Items and To Read entries carry age_days — how many days they've sat untouched. When asked to tidy, de-stale, or clean up, use it: propose removing old, low-value To Read links (and stale items), and always name exactly what you're removing so it's easy to review before Apply. Be concise and act rather than over-explaining.`;

// Only sent when the matching tool groups are loaded.
const EXTRA = `
- Goals notepad: move a task there (move_to_goals) when it's really a goal/theme, not an action. You can also read and rewrite the whole notepad (read_goals → write_goals) to reorganize, tidy, or add/remove goal lines under **Subsection** headers.
- Documents: files the user has attached, kept in the vault. Use list_documents to see them and read_document to read one when the user refers to a file, or asks you to summarize, use, or pull from it.
- Vault writes: you can PROPOSE edits to notes (append_to_note, create_note). These are ALWAYS staged for the user to review and Apply — never silently written. Use them to file information into a note, make a new note, or wire notes and todos together (add a [[note]] to a todo with edit_title, and/or append a link back to the todos in the note). Keep note edits small and clearly labeled; don't rewrite whole notes.
- Vault notes: the user's other markdown notes in the vault (list_notes, read_note, search_vault) — read-only. Use them when a todo references a note (e.g. a [[wikilink]]), or the user asks about their notes. Cite notes by name; never invent note contents. list_notes and read_note include each note's created/modified date — weigh recency (a note written long ago may be stale; a recent one is current), and prefer the most recently updated note when several could match.
- Vault cleanup: you can help reorganize the vault (vault_overview, find_duplicate_notes, move_note, trash_note) — see VAULT CLEANUP below. Like all note edits, moves and trashes are STAGED and only happen when the user approves and Applies.

GOALS ↔ TODOS. Keep them loosely in sync. Goals are the "big rocks"; the weekly Top 5 and the daily "Today" set should mostly advance a Goal. When proposing a Top 5 or planning a day, favor items that ladder up to a Goal. During reviews, check both directions: flag Goals with no supporting todos, and active Urgent/Top 5 items that don't advance any Goal — surface these as gentle observations, not automatic changes.

ACTIVITY LOG. Notes can accumulate a dated history. When the user COMPLETES a todo whose title links a note ([[Note]]), a line is auto-appended to that note's "## Log" section — but only if the note already HAS one. So to "set up activity logs" or "start tracking X", use append_to_note to add a short "## Log" section to the relevant notes (staged for review); once it exists, future completions record there automatically. When capturing or editing a todo that's clearly about a person, project, or goal the user keeps a note for, suggest linking it with [[Name]] so finishing it gets recorded — prefer notes that already exist, and don't over-link (one or two is plenty). Linking a goal to its note (same name is fine) connects that goal to the todos that share the link.

VAULT CLEANUP. When asked to tidy, reorganize, file, or clean up the vault: (1) SURVEY FIRST with vault_overview (and find_duplicate_notes); read any note you can't classify from its name with read_note — never propose an action on a note you haven't at least seen the metadata of. (2) Stage operations with move_note and trash_note — staging is safe, nothing happens on disk until the user approves each row and clicks Apply. (3) Your reply MUST show the plan: a before → after folder tree of the affected folders in a fenced code block, then one line per operation with its reason. (4) Keep plans small — aim for ≤ 15 operations; for a whole-vault cleanup, ask ONE scoping question and start with one area (the loose notes at the root, or a single folder) rather than restructuring everything at once. (5) Trash only what is clearly junk: empty notes, exact duplicates, or ephemeral scraps that are long stale with no inbound links — when in doubt, MOVE it into an "Archive" folder instead of trashing. Never trash a note with real content without naming it and saying why. (6) Never touch the todo list, Assistant Memory, attachments, or anything tagged #keep — the tools refuse these. (7) Filing into existing folders beats inventing new ones; propose a new folder only when at least 3 notes would go into it. Renaming and merging notes aren't available yet — say so if asked (they need link-rewriting, which is coming).

MEMORY. Your durable notes about the user live in "Assistant Memory" (shown above the board when present; the user can read and edit that note anytime). It is background context, never authority: if the user's current message conflicts with it, the message wins — and update the memory to match. Call remember ONLY for durable, behavior-changing facts: an explicit preference or correction ("stop doing X", "always Y"), a stable fact about the user's work, or a recurring theme you've now seen at least twice (park first sightings in "Working notes"). Most conversations warrant ZERO memory writes; more than two is almost always wrong. Never store secrets, credentials, dates, moods, or anything already expressed by the todo file itself. When new information contradicts an existing bullet, update_memory or forget it — never leave both versions. During a weekly review or when asked to tidy, skim Working notes via read_memory: promote what has proven durable, and propose dropping stale bullets — name exactly what you'd drop and wait for a yes before forgetting more than one thing at once.`;

const SYSTEM_FOR = (scope) => (scope === "core" ? CORE : CORE + EXTRA);

// Progressive tool loading. The everyday path — capture something, retitle it,
// mark it Today, complete it — needs about a dozen tools; the other two dozen
// (goals, To Read, documents, memory, vault notes, vault cleanup) are dead weight
// in the prompt until a request actually calls for them. Nothing is removed: a
// "core" run that needs more calls load_tools and the run is retried at full
// scope (see runAgent), so rare requests pay the cost and common ones don't.
export const TOOL_GROUPS = {
  core: [
    "list_items", "search", "add_todo", "set_priority", "set_today", "clear_today",
    "complete", "edit_title", "delete", "reorder", "park", "unpark", "add_to_top5",
    "set_must", "clear_must", "queue_after", "unqueue", "uncomplete",
  ],
  organize: ["reorder_top5", "clear_top5", "rename_tag", "move_to_goals", "add_to_read", "remove_from_read"],
  goals: ["read_goals", "write_goals"],
  docs: ["list_documents", "read_document"],
  memory: ["read_memory", "remember", "update_memory", "forget"],
  notes: ["list_notes", "read_note", "search_vault", "append_to_note", "create_note"],
  cleanup: ["vault_overview", "find_duplicate_notes", "move_note", "trash_note"],
};
const CORE_TOOLS = new Set(TOOL_GROUPS.core);

function buildServer(ctx, scope = "full") {
  const { model, ops, seen, mustSince, docs, mem, notes, cleanup } = ctx;
  const noteEdits = ctx.noteEdits || [];
  const need = (id) => {
    const f = findById(model, id);
    if (!f) throw new Error(`No item with id ${id}`);
    return f;
  };
  const move = (f, to) => {
    releaseFollower(f.arr, f.idx);   // whatever was queued behind it is promoted
    f.arr.splice(f.idx, 1);
    f.item.blocked = false;
    model[to].push(f.item);
    normalizeChains(model);
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
      return ok(JSON.stringify(cap.map((it, i) => ({
        ...itemView(it, cap, i),
        age_days: ageDays(seen, it.title),
        ...(it.must ? { must_days: mustDays(mustSince, it.title) } : {}),
      }))));
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
    tool("clear_today", "Remove the Today mark from an item (also clears Must).", { id: z.string() }, async ({ id }) => {
      const f = need(id); f.item.starred = false; f.item.must = false; reflowUrgent(model);
      ops.push(`cleared Today on "${f.item.title}"`);
      return ok("Cleared.");
    }),
    tool("set_must", `Promote a Today item to Must — a hard commitment for today, capped at ${MUST_CAP}. Only use it when the user says something is genuinely non-negotiable; if the cap is full, tell them which Must they'd have to drop and let THEM choose rather than picking one yourself.`, { id: z.string() }, async ({ id }) => {
      const f = need(id);
      if (f.item.must) return ok("Already a Must.");
      if (countMusts(model) >= MUST_CAP) {
        const current = model.urgent.filter((i) => i.must).map((i) => `${i.id} “${i.title}”`).join(", ");
        return ok(`Can't — Must is full at ${MUST_CAP}: ${current}. Ask the user which one to clear first; do NOT clear one on your own.`);
      }
      if (f.bucket !== "urgent") move(f, "urgent");
      f.item.must = true; f.item.starred = true; reflowUrgent(model);
      ops.push(`marked "${f.item.title}" as Must`);
      return ok("Marked Must.");
    }),
    tool("clear_must", "Demote a Must back to an ordinary Today item. Use this when the user says something is no longer a hard commitment, or when they re-scope the day.", { id: z.string() }, async ({ id }) => {
      const f = need(id); f.item.must = false; reflowUrgent(model);
      ops.push(`cleared Must on "${f.item.title}"`);
      return ok("Cleared — still Today.");
    }),
    tool("queue_after", "Queue an item to happen AFTER the item directly above it in the same section — for steps that genuinely must happen in order. A queued item is not startable, so this clears Today/Must on it. If the item isn't already directly below the one it should follow, use `reorder` first. Don't queue things that merely feel related; only real sequencing.", { id: z.string() }, async ({ id }) => {
      const f = need(id);
      if (f.item.blocked) return ok("Already queued.");
      if (!["urgent", "normal"].includes(f.bucket)) return ok("Only Urgent and Normal items can be queued.");
      if (f.idx === 0) return ok("Nothing above this to queue behind — reorder it below the item it should follow first.");
      f.item.blocked = true; f.item.starred = false; f.item.must = false;
      if (f.bucket === "urgent") reflowUrgent(model);
      const after = blockerOf(f.arr, f.arr.indexOf(f.item));
      ops.push(`queued "${f.item.title}" after "${after?.title ?? "the item above"}"`);
      return ok(`Queued after "${after?.title ?? "the item above"}".`);
    }),
    tool("unqueue", "Release an item from its queue so it can be worked on independently.", { id: z.string() }, async ({ id }) => {
      const f = need(id);
      if (!f.item.blocked) return ok("Not queued.");
      f.item.blocked = false;
      ops.push(`released "${f.item.title}" from its queue`);
      return ok("Released.");
    }),
    tool("uncomplete", "Put a completed item back into Urgent, unchecked — for when something was ticked off by mistake.", { id: z.string() }, async ({ id }) => {
      const f = need(id);
      if (f.bucket !== "completed") return ok("That item isn't in Completed.");
      f.item.checked = false;
      releaseFollower(f.arr, f.idx);
      f.arr.splice(f.idx, 1);
      model.urgent.push(f.item);
      reflowUrgent(model);
      ops.push(`un-completed "${f.item.title}"`);
      return ok("Back in Urgent.");
    }),
    tool("move_to_goals", "Move an item into the Goals notepad (optionally under a **subsection**).", { id: z.string(), subsection: z.string().optional() }, async ({ id, subsection }) => {
      const f = need(id);
      insertGoal(model, f.item.title, subsection);
      releaseFollower(f.arr, f.idx);
      f.arr.splice(f.idx, 1);
      ops.push(`moved "${f.item.title}" to Goals${subsection ? ` (${subsection})` : ""}`);
      return ok("Moved to Goals.");
    }),
    tool("add_to_top5", "Add a title to this week's Top 5.", { title: z.string() }, async ({ title }) => {
      model.top5.push(newItem(title));
      ops.push(`added "${title}" to Top 5`);
      return ok("Added to Top 5.");
    }),
    tool("reorder_top5", "Reorder this week's Top 5. Pass the item ids top-to-bottom in the new order (ids from list_items \"top5\"); any ids you omit keep their relative order at the end.", { order: z.array(z.string()) }, async ({ order }) => {
      const byId = new Map(model.top5.map((it) => [it.id, it]));
      const next = [], seen = new Set();
      for (const id of order) { const it = byId.get(id); if (it && !seen.has(id)) { next.push(it); seen.add(id); } }
      for (const it of model.top5) if (!seen.has(it.id)) next.push(it);
      model.top5 = next;
      ops.push("reordered Top 5");
      return ok("Top 5 reordered.");
    }),
    tool("clear_top5", "Clear all items from this week's Top 5 (e.g. to start a fresh week). Removes them from Top 5 only — it doesn't delete anything elsewhere.", {}, async () => {
      const n = model.top5.length;
      model.top5 = [];
      ops.push(`cleared Top 5${n ? ` (${n})` : ""}`);
      return ok(n ? `Cleared ${n} from Top 5.` : "Top 5 was already empty.");
    }),
    tool("reorder", "Reorder an item within its bucket (Urgent or Normal) to prioritize it — place it at the top or bottom, or just above/below another item by id. In Urgent, Today items always stay above the rest.", { id: z.string(), position: z.enum(["top", "bottom"]).optional(), before: z.string().optional(), after: z.string().optional() }, async ({ id, position, before, after }) => {
      const f = need(id);
      if (!["urgent", "normal"].includes(f.bucket)) return ok("Only Urgent or Normal items can be reordered.");
      const arr = f.arr; releaseFollower(arr, f.idx); arr.splice(f.idx, 1);
      let idx = 0;
      if (position === "bottom") idx = arr.length;
      else if (before) { const t = arr.findIndex((it) => it.id === before); idx = t === -1 ? arr.length : t; }
      else if (after) { const t = arr.findIndex((it) => it.id === after); idx = t === -1 ? arr.length : t + 1; }
      arr.splice(idx, 0, f.item);
      if (f.bucket === "urgent") reflowUrgent(model);
      ops.push(`reordered "${f.item.title}"`);
      return ok("Reordered.");
    }),
    tool("rename_tag", "Rename a #tag everywhere it appears in item titles — use to tidy or merge tags (e.g. #ai → #AI). Give the tags without the leading #.", { from: z.string(), to: z.string() }, async ({ from, to }) => {
      const a = String(from).replace(/^#/, "").trim(), b = String(to).replace(/^#/, "").trim();
      if (!a || !b) return ok("Give both the current and the new tag.");
      const re = new RegExp(`(^|\\s)#${a.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![\\w/-])`, "g");
      let count = 0;
      for (const bucket of ["urgent", "normal", "top5", "completed", "parked"]) for (const it of model[bucket] ?? []) {
        if (re.test(it.title)) { it.title = it.title.replace(re, `$1#${b}`); count++; } re.lastIndex = 0;
      }
      ops.push(`renamed #${a} → #${b} (${count})`);
      return ok(count ? `Renamed #${a} → #${b} on ${count} item${count === 1 ? "" : "s"}.` : `No items use #${a}.`);
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
    tool("read_note", "Read a note from the vault by name or path — a [[wikilink]] name works. Returns the note's markdown plus its created/modified date (read-only).", { name: z.string() }, async ({ name }) => {
      const r = notes?.read(name);
      if (!r) return ok("Vault notes are unavailable.");
      return ok(r.error || `# ${r.path}  (created ${r.created}, modified ${r.modified})\n\n${r.content}`);
    }),
    tool("search_vault", "Search the full text of all notes in the vault for a query. Returns matching notes with line snippets — use it to answer questions about the user's notes or follow a reference from a todo.", { query: z.string() }, async ({ query }) => ok(notes ? JSON.stringify(notes.search(query)) : "Vault notes are unavailable.")),
    tool("append_to_note", "Append text to a vault note (creates it if it doesn't exist). STAGED for the user to review — nothing is written until they Apply. Use to file takeaways into a note, or to add a backlink (e.g. append '- [[Big Rocks]]' to a note so it points back to the todos).", { name: z.string(), content: z.string() }, async ({ name, content }) => {
      noteEdits.push({ op: "append", name, content, label: `Append to “${name}”: ${String(content).trim().replace(/\s+/g, " ").slice(0, 50)}` });
      return ok(`Staged an append to “${name}” — the user will review and Apply it.`);
    }),
    tool("create_note", "Create a new vault note. STAGED for the user to review — nothing is written until they Apply.", { name: z.string(), content: z.string() }, async ({ name, content }) => {
      noteEdits.push({ op: "create", name, content, label: `Create note “${name}”` });
      return ok(`Staged a new note “${name}” — the user will review and Apply it.`);
    }),
    tool("vault_overview", "Survey the vault (or one folder) before tidying: a folder tree with note counts, plus each note's path, created/modified dates, size, inbound/outbound link counts, and empty/stale flags. Read-only. Call this FIRST whenever asked to tidy, reorganize, file, or clean up notes — never propose an action on a note you haven't at least seen here.", { folder: z.string().optional() }, async ({ folder }) => ok(cleanup ? JSON.stringify(cleanup.overview(folder)) : "Vault cleanup is unavailable.")),
    tool("find_duplicate_notes", "Find likely duplicate notes: identical content, and title variants like “Foo”, “Foo (copy)”, “Foo 2”. Read-only. Use during a cleanup to spot merge/trash candidates.", {}, async () => ok(cleanup ? JSON.stringify(cleanup.duplicates()) : "Vault cleanup is unavailable.")),
    tool("move_note", "STAGE moving a note into another folder (the folder is created on Apply if it doesn't exist). Nothing moves until the user approves the row and clicks Apply. Use exact paths from vault_overview; to_folder is vault-relative (\"\" for the root). Bare [[wikilinks]] keep working after a move; the move is refused if other notes link to this one by folder-path.", { path: z.string(), to_folder: z.string(), reason: z.string() }, async ({ path, to_folder, reason }) => {
      if (!cleanup) return ok("Vault cleanup is unavailable.");
      const r = cleanup.stageMove({ path, to_folder, reason }, noteEdits);
      if (r.error) return ok(r.error);
      noteEdits.push(r.intent);
      return ok(`Staged: ${r.intent.label} — the user will review and Apply it.`);
    }),
    tool("trash_note", "STAGE moving a note to the app's recoverable trash (.bigrocks/trash — NEVER a hard delete; the user can restore it). Refused if other notes link to it, unless you pass force_linked_ok AFTER telling the user. Never trashes a note tagged #keep, your todo list, or Assistant Memory. Give a clear reason — it's shown on the review row.", { path: z.string(), reason: z.string(), force_linked_ok: z.boolean().optional() }, async ({ path, reason, force_linked_ok }) => {
      if (!cleanup) return ok("Vault cleanup is unavailable.");
      const r = cleanup.stageTrash({ path, reason, force_linked_ok }, noteEdits);
      if (r.error) return ok(r.error);
      noteEdits.push(r.intent);
      return ok(`Staged: ${r.intent.label} — the user will review and Apply it.`);
    }),
  ];

  if (scope !== "core") return createSdkMcpServer({ name: "todo", version: "0.1.0", tools });

  // Core scope: the everyday tools, plus one escape hatch. load_tools doesn't load
  // anything itself — it records the need and lets the turn end, and runAgent then
  // replays the request at full scope (ops are rolled back first, so nothing is
  // applied twice).
  const core = tools.filter((t) => CORE_TOOLS.has(t.name));
  core.push(tool(
    "load_tools",
    "Load the rest of your tools. The tools you can see cover capturing, editing, reprioritising, completing, parking and Top 5. Call this FIRST — before answering — if the request needs anything else: the Goals notepad, To Read, attached documents, your memory, or the user's vault notes (reading, searching, editing, or reorganising them). Say nothing else in that turn; the request is re-run with every tool available.",
    { reason: z.string().describe("What you need that the current tools don't cover, in a few words.") },
    async ({ reason }) => { ctx.requestWiden?.(reason); return ok("Reloading with the full tool set…"); },
  ));
  return createSdkMcpServer({ name: "todo", version: "0.1.0", tools: core });
}

const NORMAL_CAP = 40; // list this many Normal ids inline; the rest via list_items/search
export function snapshot(model, docs, mustSince) {
  // Must is called out with its streak so the assistant can spot re-commit theater
  // (the same item promised every morning) without another tool call.
  const mark = (it) => {
    if (it.blocked) return " ·after↑";
    if (!it.must) return it.starred ? " ·Today" : "";
    const d = mustDays(mustSince, it.title);
    return d === null || d < 1 ? " ·MUST" : ` ·MUST (${d}d)`;
  };
  const u = model.urgent.map((it) => `  ${it.id}${mark(it)} — ${it.title}`).join("\n");
  const tags = [...new Set(model.normal.flatMap((it) => tagsOf(it.title)))];
  const subs = (model.goals?.rawLines ?? []).filter((l) => /^\*\*.+\*\*$/.test(l.trim())).map((l) => l.trim());
  const top5 = model.top5.map((it) => `  ${it.id} — ${it.title}`).join("\n");
  // Normal carries ids too (capped) so "delete it" / "move that" resolve without a
  // search round-trip. Overflow beyond the cap is reachable via list_items/search.
  const nShown = model.normal.slice(0, NORMAL_CAP);
  const n = nShown.map((it) => `  ${it.id} — ${it.title}`).join("\n");
  const nMore = model.normal.length > NORMAL_CAP ? `\n  …and ${model.normal.length - NORMAL_CAP} more (use list_items "normal")` : "";
  const documents = docs?.list?.() ?? [];
  return [
    `Urgent (${model.urgent.length}) — ${countMusts(model)}/${MUST_CAP} Must:`, u || "  (none)",
    `Normal (${model.normal.length}). Tags in use: ${tags.length ? tags.map((t) => "#" + t).join(" ") : "(none)"}`,
    (n || "  (none)") + nMore,
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
  set_must: "Committing to a Must", clear_must: "Clearing a Must",
  queue_after: "Queuing a step", unqueue: "Releasing from a queue", uncomplete: "Putting it back",
  move_to_goals: "Moving to Goals", add_to_top5: "Updating Top 5",
  reorder_top5: "Reordering Top 5", clear_top5: "Clearing Top 5", reorder: "Reordering", rename_tag: "Renaming a tag",
  add_to_read: "Adding to To Read", remove_from_read: "Pruning To Read",
  complete: "Completing an item", edit_title: "Editing an item", delete: "Deleting an item",
  park: "Parking an item", unpark: "Un-parking an item",
  list_documents: "Checking your documents", read_document: "Reading a document",
  read_memory: "Checking my notes", remember: "Noting something for later",
  update_memory: "Updating my notes", forget: "Forgetting a note",
  list_notes: "Listing your notes", read_note: "Reading a note", search_vault: "Searching your vault",
  append_to_note: "Drafting a note edit", create_note: "Drafting a new note",
  vault_overview: "Surveying your vault", find_duplicate_notes: "Looking for duplicates",
  move_note: "Proposing a move", trash_note: "Proposing to trash",
  load_tools: "Getting more tools",
};
const toolLabel = (name) => {
  const bare = String(name || "").replace(/^mcp__todo__/, "");
  return TOOL_LABELS[bare] || bare.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase());
};

export async function runAgent({ model, ops, seen, mustSince, message, sessionId, abortController, onEvent, docs, mem, notes, cleanup, noteEdits, llmModel, effort, maxTurns = 24, fallbackModel, toolScope = "full", recentChat = [] }) {
  const emit = (event) => { try { onEvent?.(event); } catch {} };
  // Set by the core-scope load_tools tool when the model finds it needs more than
  // the everyday set; consumed by withWidening below.
  let widenReason = null;
  const ctx = { model, ops, seen, mustSince, docs, mem, notes, cleanup, noteEdits, requestWiden: (reason) => { widenReason = reason || "more tools"; } };
  const serverFor = (scope) => buildServer(ctx, scope);
  const memText = mem?.injectionText?.() || "";
  const board = `Current board:\n${snapshot(model, docs, mustSince)}\n\nUser: ${message}`;
  // A compact recap of the last few turns — folded in only when we start a FRESH
  // session (first message, or after recovering from an overflow), so continuity
  // survives without replaying the whole transcript.
  const recentBlock = recentChat.length
    ? `Recent conversation (most recent last):\n${recentChat.map((m) => `${m.role === "you" ? "User" : "Assistant"}: ${String(m.text || "").slice(0, 600)}`).join("\n")}\n\n`
    : "";
  const memBlock = memText ? `Assistant Memory (background — the user's current message always wins):\n${memText}\n\n` : "";
  // On resume the model already has the memory and history from earlier turns —
  // re-sending them every message is what grows the prompt until it overflows.
  const promptFor = (resumeId) => (resumeId ? board : memBlock + recentBlock + board);

  const opsBaseline = ops.length;
  const noteEditsBaseline = noteEdits.length; // note edits staged before this message

  const attempt = async (resumeId, modelOverride, scope = toolScope) => {
    const usedModel = modelOverride || llmModel;
    const prompt = promptFor(resumeId);
    let reply = "";
    let session = resumeId;
    let subtype = null;
    const q = query({
      prompt,
      options: {
        systemPrompt: SYSTEM_FOR(scope),
        settingSources: [],
        mcpServers: { todo: serverFor(scope) },
        // The SDK ships every built-in Claude Code tool (Bash, Edit, WebFetch, …)
        // in the prompt by default — ~17.5k tokens this app can never use, paid on
        // every message. canUseTool only denies them at *call* time, and allowedTools
        // doesn't remove them either; disallowedTools is what keeps them out of the
        // prompt entirely. Keep this list in sync-ish with the SDK: an unknown name
        // here is harmless, a missing one just costs tokens.
        disallowedTools: BUILTIN_TOOLS,
        maxTurns,
        ...(usedModel ? { model: usedModel } : {}),
        // Effort never rides on Haiku — the API rejects it.
        ...(effort && usedModel !== "haiku" ? { effort } : {}),
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
      } else if (msg.type === "result") {
        subtype = msg.subtype || null;
        if (msg.result && !reply) reply = msg.result;
      }
    }
    return { reply: reply.trim(), sessionId: session, subtype, model: usedModel };
  };

  // A fast-tier (Haiku, low turn budget) run that ends in max_turns / an execution
  // error rolls back its ops and retries once on a stronger model. Hard signals
  // only — no parsing the reply for "uncertainty".
  const withEscalation = async (resumeId, scope) => {
    const first = await attempt(resumeId, llmModel, scope);
    const flailed = /max_turns|error/i.test(first.subtype || "");
    if (fallbackModel && fallbackModel !== first.model && flailed) {
      ops.length = opsBaseline;
      emit({ kind: "tool", label: `Escalating to ${fallbackModel}…` });
      return await attempt(resumeId, fallbackModel, scope);
    }
    return first;
  };

  // Progressive tool loading. A core-scope run that calls load_tools is replayed
  // once at full scope — ops rolled back first, and starting a FRESH session so the
  // model doesn't re-read a transcript where it lacked the tools. Only ever widens
  // once per message: a second load_tools at full scope has nothing left to load.
  const withWidening = async (resumeId) => {
    widenReason = null;
    const first = await withEscalation(resumeId, toolScope);
    if (toolScope !== "core" || !widenReason) return first;
    ops.length = opsBaseline;
    noteEdits.length = noteEditsBaseline;
    emit({ kind: "tool", label: "Loading the rest of my tools…" });
    return await withEscalation(undefined, "full");
  };

  // A resumed conversation can outgrow the context window ("prompt is too long").
  // Recover once by dropping the transcript and starting a FRESH session — the
  // prompt then carries the current board plus a compact recap of recent turns
  // (promptFor), so the model keeps continuity without the full history.
  const OVERFLOW = /prompt is too long|too many tokens|context (?:window|length|limit)|exceed[^.]*(?:context|token)|input (?:is )?too long|maximum context/i;
  let recovered = false;

  try {
    const r = await withWidening(sessionId);
    // Some overflows arrive as an error *result* (empty reply) rather than a throw.
    if (sessionId && !recovered && !r.reply && OVERFLOW.test(r.subtype || "")) {
      recovered = true;
      ops.length = opsBaseline;
      emit({ kind: "tool", label: "Conversation got long — starting fresh…" });
      return await withWidening(undefined);
    }
    return r;
  } catch (e) {
    const m = String(e?.message || e);
    // A saved session can vanish (history cleared, a different machine, an expired
    // id) — retry fresh. Same recovery covers a context overflow on resume.
    const stale = sessionId && /no conversation found|conversation not found|session id|invalid session|session not found/i.test(m);
    const overflow = OVERFLOW.test(m);
    if (!recovered && (stale || (overflow && sessionId))) {
      recovered = true;
      ops.length = opsBaseline;
      if (overflow) emit({ kind: "tool", label: "Conversation got long — starting fresh…" });
      return await withWidening(undefined);
    }
    if (overflow) throw new Error("This conversation got too long to continue. Click “Clear chat” and ask again — for a big weekly review, tackle one section at a time.");
    throw e;
  }
}
