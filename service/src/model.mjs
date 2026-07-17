// Helpers for the in-memory working model the agent mutates. Ids are ephemeral
// (assigned per load, never serialized) so tools can reference items stably
// within a session.
import { tagsOf, linksOf } from "./parse.mjs";

let counter = 0;
const BUCKETS = ["urgent", "normal", "top5", "completed", "deleted", "parked"];

export function assignIds(model) {
  for (const b of BUCKETS) for (const it of model[b]) if (!it.id) it.id = "i" + ++counter;
  return model;
}

export function findById(model, id) {
  for (const bucket of BUCKETS) {
    const arr = model[bucket];
    const idx = arr.findIndex((it) => it.id === id);
    if (idx !== -1) return { item: arr[idx], bucket, arr, idx };
  }
  return null;
}

// Stable star-first ordering: "Today" (starred) items float to the top of Urgent.
export function reflowUrgent(model) {
  const starred = model.urgent.filter((i) => i.starred);
  const rest = model.urgent.filter((i) => !i.starred);
  model.urgent = [...starred, ...rest];
}

export function newItem(title, { starred = false, checked = false } = {}) {
  return { checked, starred, title, id: "i" + ++counter };
}

// A compact, id-bearing view for the agent's read tools and the web UI.
export function itemView(it) {
  return { id: it.id, title: it.title, today: !!it.starred, done: !!it.checked, tags: tagsOf(it.title), links: linksOf(it.title) };
}

// Server-side near-duplicate detection (mirrors the client quick-add check) —
// used by the capture endpoint, which has no browser to run the client version.
const DUP_STOP = new Set(["the", "and", "for", "with", "from", "this", "that", "your", "you", "are", "was", "get", "got", "new", "now", "out", "its"]);
const dupToks = (t) => [...new Set(String(t).toLowerCase().replace(/#[\w/-]+/g, " ").replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter((w) => w.length >= 3 && !DUP_STOP.has(w)))];
function dupScore(a, b) {
  const A = dupToks(a), B = dupToks(b);
  if (!A.length || !B.length) return 0;
  const bs = new Set(B);
  let inter = 0;
  for (const w of A) if (bs.has(w)) inter++;
  if (!inter) return 0;
  return Math.max((inter / Math.min(A.length, B.length)) * 0.92, inter / (A.length + B.length - inter));
}
export function findDuplicate(model, title) {
  let best = null;
  for (const b of ["urgent", "normal", "top5"]) for (const it of model[b] ?? []) {
    const s = dupScore(title, it.title);
    if (s >= 0.67 && (!best || s > best.score)) best = { ...itemView(it), bucket: b, score: s };
  }
  return best;
}

// Search everywhere: item titles across Urgent/Normal/Top 5/Completed, plus the
// Goals notepad and the To Read list. Pure (testable) — the agent's search tool
// is a thin wrapper over this.
export function searchModel(model, query) {
  const q = String(query ?? "").toLowerCase().trim();
  if (!q) return [];
  const hits = [];
  for (const b of ["urgent", "normal", "top5", "completed"])
    for (const it of model[b] ?? []) if (it.title.toLowerCase().includes(q)) hits.push({ ...itemView(it), bucket: b });
  for (const l of model.goals?.rawLines ?? []) { const t = l.trim(); if (t && t.toLowerCase().includes(q)) hits.push({ text: t.replace(/^[-*]\s+/, ""), bucket: "goals" }); }
  for (const l of model.toread?.rawLines ?? []) { const t = l.replace(/^-\s+/, "").trim(); if (t && t.toLowerCase().includes(q)) hits.push({ text: t, bucket: "toread" }); }
  return hits;
}
