// Direct (non-agent) mutations on the working draft. Same semantics the agent
// tools use, invoked straight from the UI (click a checkbox, quick-add, delete).
// These add to the draft like agent edits — nothing persists until Apply.
import { findById, reflowUrgent, newItem, MUST_CAP, countMusts } from "./model.mjs";

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
      f.item.must = false;
      move(model, f, "completed");
      return `completed "${f.item.title}"`;
    }
    // Top 5 are weekly commitments, not ordinary todos — checking one strikes it
    // in place (stays in Top 5) rather than moving it to Completed.
    case "toggleDone": {
      const f = need(model, a.id);
      f.item.checked = !f.item.checked;
      return `${f.item.checked ? "checked off" : "un-checked"} "${f.item.title}"`;
    }
    case "delete": {
      const f = need(model, a.id);
      f.item.checked = true;
      f.item.must = false;
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
    case "park": {
      const f = need(model, a.id);
      if (f.bucket === "parked") return null;
      f.item.checked = false; f.item.starred = false; f.item.must = false;
      move(model, f, "parked");
      return `parked "${f.item.title}"`;
    }
    case "unpark": {
      const f = need(model, a.id);
      if (f.bucket !== "parked") throw new Error("only parked items can be un-parked");
      move(model, f, "normal");
      return `un-parked "${f.item.title}"`;
    }
    case "archiveCompleted": {
      if (!model.completed.length) return null;
      const count = model.completed.length;
      model.deleted.push(...model.completed);
      model.completed = [];
      return `moved ${count} completed item${count === 1 ? "" : "s"} to deleted`;
    }
    case "clearDeleted": {
      if (!model.deleted.length) return null;
      const count = model.deleted.length;
      model.deleted = [];
      return `emptied trash (${count} item${count === 1 ? "" : "s"})`;
    }
    case "toggleToday": {
      const f = need(model, a.id);
      if (f.item.starred) {
        f.item.starred = false;
        f.item.must = false; // dropping the intention drops the commitment with it
      } else {
        if (f.bucket !== "urgent") move(model, f, "urgent");
        f.item.starred = true;
      }
      reflowUrgent(model);
      return `${f.item.starred ? "marked" : "cleared"} Today on "${f.item.title}"`;
    }
    // Must is promoted FROM Today, not from anywhere: a commitment is an intention
    // you escalated. Toggling off demotes back to Today rather than off the list.
    case "toggleMust": {
      const f = need(model, a.id);
      if (f.item.must) {
        f.item.must = false;
        reflowUrgent(model);
        return `cleared Must on "${f.item.title}" (still Today)`;
      }
      if (countMusts(model) >= MUST_CAP) {
        const current = model.urgent.filter((i) => i.must).map((i) => `“${i.title}”`).join(", ");
        throw new Error(`Must is capped at ${MUST_CAP}. Clear one first — right now it's ${current}.`);
      }
      if (f.bucket !== "urgent") move(model, f, "urgent");
      f.item.must = true;
      f.item.starred = true;
      reflowUrgent(model);
      return `marked "${f.item.title}" Must`;
    }
    case "setPriority": {
      const f = need(model, a.id);
      const to = a.bucket === "normal" ? "normal" : "urgent";
      f.item.starred = false;
      f.item.must = false;
      if (f.bucket !== to) {
        move(model, f, to);
        if (to === "urgent") reflowUrgent(model);
      }
      return `moved "${f.item.title}" to ${to}`;
    }
    // Bulk sibling of setPriority — moves several selected items to Urgent or
    // Normal at once (clearing Today on each) so a multi-select is one activity
    // entry / one undo step. Missing ids are skipped rather than fatal.
    case "setPriorityMany": {
      const to = a.bucket === "normal" ? "normal" : "urgent";
      const ids = Array.isArray(a.ids) ? a.ids : [];
      let count = 0;
      let last = "";
      for (const id of ids) {
        const f = findById(model, id);
        if (!f) continue;
        f.item.starred = false;
        f.item.must = false;
        if (f.bucket !== to) move(model, f, to);
        count++;
        last = f.item.title;
      }
      if (to === "urgent") reflowUrgent(model);
      if (!count) return null;
      return count === 1 ? `moved "${last}" to ${to}` : `moved ${count} items to ${to}`;
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
      // Must / Today / rest are three ordered groups — a manual nudge may not cross
      // a group boundary (use toggleMust / toggleToday for that).
      const grp = (i) => (i.must ? 0 : i.starred ? 1 : 2);
      if (j < 0 || j >= arr.length || grp(arr[j]) !== grp(it)) return null;
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
      const destination = ["top5", "today", "urgent", "normal"].includes(a.bucket) ? a.bucket : null;
      if (!destination) throw new Error("items can only be moved to Top 5, Today, Urgent, or Normal");
      if (a.targetId === a.id) return null;
      const source = need(model, a.id);
      if (!["top5", "urgent", "normal"].includes(source.bucket)) throw new Error("this item cannot be reordered");
      if ((source.bucket === "top5") !== (destination === "top5")) throw new Error("Top 5 items can only be reordered within Top 5");

      const destinationBucket = ["today", "urgent"].includes(destination) ? "urgent" : destination;
      let targetItem = null;
      if (a.targetId) {
        const target = need(model, a.targetId);
        const targetDestination = target.bucket === "urgent" ? (target.item.starred ? "today" : "urgent") : target.bucket;
        if (targetDestination !== destination) throw new Error("drop target is not in the destination list");
        targetItem = target.item;
      }

      const item = source.item;
      const wasBucket = source.bucket === "urgent" ? (item.starred ? "today" : "urgent") : source.bucket;
      source.arr.splice(source.idx, 1);
      item.starred = destination === "today";
      if (destination !== "today") item.must = false;
      const arr = model[destinationBucket];
      let insertAt;
      if (targetItem) {
        const targetIndex = arr.indexOf(targetItem);
        insertAt = targetIndex + (a.position === "after" ? 1 : 0);
      } else if (destination === "today") {
        const firstUrgent = arr.findIndex((i) => !i.starred);
        insertAt = firstUrgent < 0 ? arr.length : firstUrgent;
      } else {
        insertAt = arr.length;
      }
      arr.splice(insertAt, 0, item);
      return wasBucket === destination
        ? `reordered "${item.title}" in ${destination}`
        : `moved "${item.title}" from ${wasBucket} to ${destination}`;
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
