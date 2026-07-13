// Direct (non-agent) mutations on the working draft. Same semantics the agent
// tools use, invoked straight from the UI (click a checkbox, quick-add, delete).
// These add to the draft like agent edits — nothing persists until Apply.
import { findById, reflowUrgent, newItem } from "./model.mjs";

const need = (model, id) => {
  const f = findById(model, id);
  if (!f) throw new Error(`No item ${id}`);
  return f;
};
const move = (model, f, to) => {
  f.arr.splice(f.idx, 1);
  model[to].push(f.item);
};

// Returns a human-readable op description, or null if the action was a no-op.
export function applyAction(model, action, a = {}) {
  switch (action) {
    case "add": {
      const title = (a.title || "").trim();
      if (!title) return null;
      const today = !!a.today;
      const bucket = today ? "urgent" : a.bucket === "normal" ? "normal" : "urgent";
      model[bucket].push(newItem(title, { starred: today }));
      if (bucket === "urgent") reflowUrgent(model);
      return `added "${title}" to ${bucket}${today ? " · Today" : ""}`;
    }
    case "complete": {
      const f = need(model, a.id);
      f.item.checked = true;
      move(model, f, "completed");
      return `completed "${f.item.title}"`;
    }
    case "delete": {
      const f = need(model, a.id);
      f.item.checked = true;
      move(model, f, "deleted");
      return `deleted "${f.item.title}"`;
    }
    case "toggleToday": {
      const f = need(model, a.id);
      if (f.item.starred) {
        f.item.starred = false;
      } else {
        if (f.bucket !== "urgent") move(model, f, "urgent");
        f.item.starred = true;
      }
      reflowUrgent(model);
      return `${f.item.starred ? "marked" : "cleared"} Today on "${f.item.title}"`;
    }
    case "setPriority": {
      const f = need(model, a.id);
      const to = a.bucket === "normal" ? "normal" : "urgent";
      if (f.bucket !== to) {
        move(model, f, to);
        if (to === "urgent") reflowUrgent(model);
      }
      return `moved "${f.item.title}" to ${to}`;
    }
    case "reorder": {
      const arr = model.urgent;
      const idx = arr.findIndex((i) => i.id === a.id);
      if (idx < 0) throw new Error("not an urgent item");
      const it = arr[idx];
      const j = idx + (a.dir === "up" ? -1 : 1);
      if (j < 0 || j >= arr.length || arr[j].starred !== it.starred) return null; // edge / would cross the Today group
      [arr[idx], arr[j]] = [arr[j], arr[idx]];
      return `moved "${it.title}" ${a.dir}`;
    }
    default:
      throw new Error(`Unknown action ${action}`);
  }
}
