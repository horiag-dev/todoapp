// Helpers for the in-memory working model the agent mutates. Ids are ephemeral
// (assigned per load, never serialized) so tools can reference items stably
// within a session.
import { tagsOf } from "./parse.mjs";

let counter = 0;
const BUCKETS = ["urgent", "normal", "top5", "completed", "deleted"];

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
  return { id: it.id, title: it.title, today: !!it.starred, done: !!it.checked, tags: tagsOf(it.title) };
}
