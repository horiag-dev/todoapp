// The vault activity ledger (Phase 1). When a LINKED todo is completed, a dated
// line is appended to each linked note's `## Log` section — so notes stop being
// only where you write things and start to accumulate what happened. Opt-in by
// the presence of `## Log` (a note without one is surfaced so you can start one
// in a click). Deterministic (produced by code from a committed completion,
// never by the agent), append-only, and undoable.
import { createNotes } from "./notes.mjs";
import { linksOf } from "./parse.mjs";

const today = () => new Date().toISOString().slice(0, 10);
const escapeRe = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// The log line for note `name`: date + ✓ + the todo title, with the SELF link
// [[name]] stripped (a note needn't link to itself) but cross-links kept — so
// Sergey's line still carries [[Proactive Insights]] and the Obsidian graph grows.
export function logLine(title, name, date = today()) {
  const self = new RegExp(`\\s*\\[\\[${escapeRe(name)}(?:\\|[^\\]]*)?(?:#[^\\]]*)?\\]\\]`, "gi");
  const stripped = String(title).replace(self, "").replace(/\s{2,}/g, " ").trim();
  return `- ${date} ✓ ${stripped}`;
}

export function createActivity(vault) {
  const notes = createNotes(vault);
  return {
    // Log a completion to every note it links. Returns { logged, suggest, undo }:
    // logged = notes that already had a `## Log` (written); suggest = linked notes
    // with no log yet (offer to start one); undo = the appended lines to reverse.
    logCompletion(title) {
      const logged = [], suggest = [], undo = [];
      for (const name of linksOf(title)) {
        const line = logLine(title, name);
        const r = notes.appendToLog(name, line);
        if (r.path) { logged.push({ note: name, path: r.path }); undo.push({ note: name, line }); }
        else if (r.noLog) suggest.push({ note: name, line });
        // r.error (ambiguous) → skip silently; a completion never blocks on a note write
      }
      return { logged, suggest, undo };
    },
    // Explicit opt-in: start a `## Log` in each note (creating the note if needed)
    // and append its pending line. This is the one-click "start logging here".
    enable(items) {
      const logged = [], undo = [];
      for (const { note, line } of items || []) {
        const r = notes.ensureLog(note, line);
        if (r.path) { logged.push({ note, path: r.path, created: r.created }); undo.push({ note, line }); }
      }
      return { logged, undo };
    },
    // Reverse a batch of log appends (remove the exact lines that were added).
    undo(entries) {
      let removed = 0;
      for (const { note, line } of entries || []) if (notes.removeLogLine(note, line).path) removed++;
      return { removed };
    },
  };
}
