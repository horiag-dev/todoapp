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

// The commitment ladder: Urgent (could do) → Today (intend to) → Must (committed).
// Must is deliberately capped — the cap is the feature. Without it Today became a
// second Urgent, which is exactly what Must exists to fix.
export const MUST_CAP = 3;
export const countMusts = (model) => model.urgent.filter((i) => i.must).length;

// --- queues ------------------------------------------------------------------
// A queue is a head item followed by consecutive `blocked` items. It's positional,
// not a graph: "blocked" just means "waits for the line above me". Split an array
// into chains so ordering can move a whole queue as one unit.
export function chainsOf(items) {
  const out = [];
  for (const it of items) {
    if (it.blocked && out.length) out[out.length - 1].push(it);
    else out.push([it]);
  }
  return out;
}

// The head of a queue can never itself be blocked — nothing sits above it to wait
// for. Runs after any structural change (complete, move, reorder, delete) so a
// queue whose head left is simply promoted rather than left dangling.
export function normalizeChains(model) {
  for (const b of ["urgent", "normal", "top5", "parked"]) {
    const arr = model[b];
    if (arr?.length && arr[0].blocked) arr[0].blocked = false;
  }
  // Completed/Deleted are archives — a stale marker there would be noise.
  for (const b of ["completed", "deleted"]) for (const it of model[b] ?? []) it.blocked = false;
}

// The item a blocked item is waiting on: simply the line above it. In a chain
// A → B → C, C waits on B (not on the head A) — that's what "sequential" means,
// and it's the same item releaseFollower promotes when B leaves.
export function blockerOf(arr, idx) {
  return idx > 0 ? arr[idx - 1] : null;
}

// Call BEFORE removing arr[idx]: whatever was queued directly behind it is
// released. Without this, "waits for the line above" would silently re-point the
// follower at an unrelated item that happened to sit above the one you removed —
// so finishing a queue head would leave the next step blocked on a stranger.
// Only the direct follower is promoted; the rest of the chain stays behind it.
export function releaseFollower(arr, idx) {
  const next = arr[idx + 1];
  if (next?.blocked) next.blocked = false;
}

// Stable rank ordering within Urgent: Must first, then the rest of Today, then
// everything else. Order *within* each group is preserved. Queues move as a unit
// and are ranked by their head, so a chain never gets torn apart by a reflow.
const rank = (i) => (i.must ? 0 : i.starred ? 1 : 2);
export function reflowUrgent(model) {
  normalizeChains(model);
  const chains = chainsOf(model.urgent);
  model.urgent = [0, 1, 2].flatMap((r) => chains.filter((c) => rank(c[0]) === r)).flat();
}

export function newItem(title, { starred = false, checked = false, must = false, blocked = false } = {}) {
  return { checked, must, blocked, starred: !blocked && (starred || must), title, id: "i" + ++counter };
}

// A compact, id-bearing view for the agent's read tools and the web UI.
// `waitingFor` is resolved here rather than left to the caller, so a blocked item
// is self-describing wherever it renders — the Today/Urgent split can separate it
// from its head on screen while the file keeps them adjacent.
export function itemView(it, arr, idx) {
  const blocker = it.blocked && arr ? blockerOf(arr, idx) : null;
  return {
    id: it.id, title: it.title, today: !!it.starred, must: !!it.must, done: !!it.checked,
    ...(it.blocked ? { blocked: true, waitingFor: blocker?.title ?? null } : {}),
    tags: tagsOf(it.title), links: linksOf(it.title),
  };
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
