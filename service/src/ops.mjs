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

// Append a bullet to the Goals notepad — under a **subsection** header if given
// and found, else at the end. Shared by direct moves and the agent tool.
export function insertGoal(model, title, subsection) {
  if (!model.goals) model.goals = { headerLine: "## 🎯 Goals", rawLines: [] };
  const lines = model.goals.rawLines;
  const line = `- ${title}`;
  if (subsection) {
    const i = lines.findIndex((l) => l.trim().toLowerCase() === `**${subsection.toLowerCase()}**`);
    if (i !== -1) {
      let j = i + 1;
      while (j < lines.length && !/^\*\*.+\*\*$/.test(lines[j].trim())) j++;
      lines.splice(j, 0, line);
      return;
    }
  }
  lines.push(line);
}

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
    case "restore": {
      const f = need(model, a.id);
      if (f.bucket !== "deleted") throw new Error("only deleted items can be restored");
      f.item.checked = false;
      move(model, f, "normal");
      return `restored "${f.item.title}" to normal`;
    }
    case "permanentDelete": {
      const f = need(model, a.id);
      if (f.bucket !== "deleted") throw new Error("only deleted items can be permanently removed");
      f.arr.splice(f.idx, 1);
      return `permanently removed "${f.item.title}"`;
    }
    case "archiveCompleted": {
      if (!model.completed.length) return null;
      const count = model.completed.length;
      model.deleted.push(...model.completed);
      model.completed = [];
      return `moved ${count} completed item${count === 1 ? "" : "s"} to deleted`;
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
    case "editTitle": {
      const f = need(model, a.id);
      const t = (a.title || "").trim();
      if (!t || t === f.item.title) return null;
      const old = f.item.title;
      f.item.title = t;
      return `renamed "${old}" → "${t}"`;
    }
    case "moveToGoals": {
      const f = need(model, a.id);
      insertGoal(model, f.item.title, a.subsection);
      f.arr.splice(f.idx, 1);
      return `moved "${f.item.title}" to Goals`;
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
    case "addTop5": {
      const title = (a.title || "").trim();
      if (!title) return null;
      model.top5.push(newItem(title));
      return `added "${title}" to Top 5`;
    }
    case "reorderTop5": {
      const arr = model.top5;
      const idx = arr.findIndex((i) => i.id === a.id);
      if (idx < 0) throw new Error("not a Top 5 item");
      const j = idx + (a.dir === "up" ? -1 : 1);
      if (j < 0 || j >= arr.length) return null;
      [arr[idx], arr[j]] = [arr[j], arr[idx]];
      return `moved "${arr[j].title}" ${a.dir}`;
    }
    case "reorderTo": {
      const bucket = ["top5", "urgent", "normal"].includes(a.bucket) ? a.bucket : null;
      if (!bucket) throw new Error("items can only be reordered in Top 5, Urgent, or Normal");
      const arr = model[bucket];
      const from = arr.findIndex((i) => i.id === a.id);
      const targetBeforeRemoval = arr.findIndex((i) => i.id === a.targetId);
      if (from < 0 || targetBeforeRemoval < 0) throw new Error("reorder item not found");
      if (from === targetBeforeRemoval) return null;
      const item = arr[from];
      const targetItem = arr[targetBeforeRemoval];
      if (bucket === "urgent" && !!item.starred !== !!targetItem.starred) {
        throw new Error("Today items can only be reordered with other Today items");
      }
      const before = arr.map((i) => i.id).join("|");
      arr.splice(from, 1);
      const target = arr.findIndex((i) => i.id === a.targetId);
      const insertAt = target + (a.position === "after" ? 1 : 0);
      arr.splice(insertAt, 0, item);
      if (before === arr.map((i) => i.id).join("|")) return null;
      return `reordered "${item.title}" in ${bucket}`;
    }
    case "clearTop5": {
      if (!model.top5.length) return null;
      const count = model.top5.length;
      model.top5 = [];
      return `cleared ${count} Top 5 item${count === 1 ? "" : "s"}`;
    }
    case "addToRead": {
      const text = (a.text || "").trim();
      if (!text) return null;
      if (!model.toread) model.toread = { headerLine: "## 📚 To Read", rawLines: [] };
      model.toread.rawLines.push(`- ${text}`);
      return `added to To Read: ${text}`;
    }
    case "removeFromRead": {
      const i = Number(a.index);
      const lines = model.toread?.rawLines ?? [];
      if (!Number.isInteger(i) || i < 0 || i >= lines.length) throw new Error("invalid To Read item");
      const [line] = lines.splice(i, 1);
      return `removed from To Read: ${line.replace(/^\-\s+/, "")}`;
    }
    case "moveToRead": {
      const f = need(model, a.id);
      if (!model.toread) model.toread = { headerLine: "## 📚 To Read", rawLines: [] };
      model.toread.rawLines.push(`- ${f.item.title}`);
      f.arr.splice(f.idx, 1);
      return `moved "${f.item.title}" to To Read`;
    }
    case "renameTag": {
      const from = String(a.from || "").replace(/^#/, "");
      const to = String(a.to || "").replace(/^#/, "");
      if (!from || !to || from === to) return null;
      const re = new RegExp(`(^|\\s)#${from.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\$&")}(?![\\w/-])`, "g");
      let count = 0;
      for (const bucket of ["urgent", "normal", "top5", "completed", "deleted"]) {
        for (const it of model[bucket]) {
          const next = it.title.replace(re, `$1#${to}`);
          if (next !== it.title) { it.title = next; count++; }
        }
      }
      return count ? `renamed #${from} to #${to} on ${count} item${count === 1 ? "" : "s"}` : null;
    }
    default:
      throw new Error(`Unknown action ${action}`);
  }
}
