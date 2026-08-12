// Private "first-seen" ledger. Lets the assistant reason about staleness
// (e.g. To Read links that have sat for a month) WITHOUT putting any dates in
// the user's markdown — the no-dates guardrail holds. Lives under .bigrocks/.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

export const keyOf = (text) => text.toLowerCase().replace(/\s+/g, " ").trim();
const ledgerPath = (vault) => join(vault.machineDir, "seen.json");

export function loadSeen(vault) {
  const p = ledgerPath(vault);
  if (!existsSync(p)) return {};
  try { return JSON.parse(readFileSync(p, "utf8")); } catch { return {}; }
}

function saveSeen(vault, seen) {
  mkdirSync(vault.machineDir, { recursive: true });
  writeFileSync(ledgerPath(vault), JSON.stringify(seen), "utf8");
}

function currentKeys(model) {
  const keys = new Set();
  for (const b of ["urgent", "normal", "top5"]) for (const it of model[b]) keys.add(keyOf(it.title));
  for (const l of model.toread?.rawLines ?? []) {
    const t = l.replace(/^-\s+/, "").trim();
    if (t) keys.add(keyOf(t));
  }
  return keys;
}

// Record firstSeen for any new keys; returns the seen map. New items start
// aging from the first time the app sees them (there's no reliable historical
// signal in a plain markdown file).
export function touch(vault, model, nowIso) {
  const seen = loadSeen(vault);
  const now = nowIso || new Date().toISOString();
  let changed = false;
  for (const k of currentKeys(model)) if (!seen[k]) { seen[k] = now; changed = true; }
  if (changed) saveSeen(vault, seen);
  return seen;
}

export function ageDays(seen, text, nowMs) {
  const iso = seen[keyOf(text)];
  if (!iso) return null;
  return Math.floor(((nowMs || Date.now()) - Date.parse(iso)) / 86400000);
}

// --- Must ledger -------------------------------------------------------------
// When each current Must became one. Same guardrail as above: the date lives in a
// private sidecar, never in the user's markdown. This is what lets the assistant
// catch re-commit theater — the same item promised every morning for a week.
const mustPath = (vault) => join(vault.machineDir, "must-since.json");

export function loadMustSince(vault) {
  const p = mustPath(vault);
  if (!existsSync(p)) return {};
  try { return JSON.parse(readFileSync(p, "utf8")); } catch { return {}; }
}

// Stamp newly-promoted Musts, drop anything no longer a Must — so demoting and
// re-promoting restarts the clock rather than resurrecting an old streak.
export function touchMust(vault, model, nowIso) {
  const prev = loadMustSince(vault);
  const now = nowIso || new Date().toISOString();
  const next = {};
  for (const it of model.urgent ?? []) if (it.must) { const k = keyOf(it.title); next[k] = prev[k] || now; }
  if (JSON.stringify(prev) !== JSON.stringify(next)) {
    try { mkdirSync(vault.machineDir, { recursive: true }); writeFileSync(mustPath(vault), JSON.stringify(next), "utf8"); } catch {}
  }
  return next;
}

export function mustDays(mustSince, text, nowMs) {
  const iso = mustSince?.[keyOf(text)];
  if (!iso) return null;
  return Math.floor(((nowMs || Date.now()) - Date.parse(iso)) / 86400000);
}
