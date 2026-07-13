// One-time migration from the legacy four-bucket format (Today / Urgent /
// This Week / Normal) to the settled model (Goals · Urgent[+star] · Normal ·
// Top 5). Runs on first load; the serializer then writes the new format.
//
//   Today  with the `TODA[Yy]` hack → Urgent + starred (hack text cleaned)
//   Today  without the hack         → Normal
//   This Week                       → Normal
//   Urgent                          → Urgent (starred only if hacked)
//   Completed / Deleted             → carried verbatim, never reprocessed
//
// Also serves as the identity/normalize pass for already-migrated files: with
// no Today/This Week present and no hacks, it reorders nothing meaningfully and
// the serializer reproduces the file.

const HACK_TOKEN_RE = /TODA[Yy][ \t]*-?[ \t]*/g;
const HACK_TAG_RE = /(^|\s)#today\b/i;

export function hasHack(title) {
  return /TODA[Yy]/.test(title) || HACK_TAG_RE.test(title);
}

// Strip the hack marker and tidy the leftover punctuation.
//   "TODAY - re-create X"            → "re-create X"
//   "Skills coverage - TODAY - talk" → "Skills coverage - talk"
//   "Sunil - TODAY REPLY"            → "Sunil - REPLY"
export function cleanHack(title) {
  let t = title;
  t = t.replace(/\s*#today\b/gi, "");
  t = t.replace(HACK_TOKEN_RE, "");
  t = t.replace(/[ \t]{2,}/g, " ");
  t = t.replace(/[ \t]+-[ \t]+-[ \t]+/g, " - "); // collapse doubled separators
  t = t.replace(/^[ \t]*-[ \t]+/, ""); // orphaned leading "- "
  t = t.replace(/[ \t]+-[ \t]*$/, ""); // orphaned trailing " -"
  return t.trim();
}

// Apply hack handling to an item destined for Urgent.
function asUrgent(item) {
  if (hasHack(item.title)) {
    return { checked: item.checked, starred: true, title: cleanHack(item.title) };
  }
  return item;
}

// Stable partition: starred items first (keeping their order), then the rest.
function starFirst(items) {
  const starred = items.filter((i) => i.starred);
  const rest = items.filter((i) => !i.starred);
  return [...starred, ...rest];
}

function collect(sections, kind) {
  return sections.filter((s) => s.kind === kind);
}
function itemsOf(sections, kind) {
  return collect(sections, kind).flatMap((s) => s.items ?? []);
}
function firstRaw(sections, kind) {
  const s = collect(sections, kind)[0];
  return s ? { headerLine: s.headerLine, rawLines: s.rawLines ?? [] } : null;
}

export function migrate(parsed) {
  const { preamble, sections } = parsed;

  const goals = firstRaw(sections, "goals");
  const toread = firstRaw(sections, "toread");

  const top5 = itemsOf(sections, "top5");

  // Urgent: existing urgent (hack-aware) + Today's hacked items (now starred).
  const existingUrgent = itemsOf(sections, "urgent").map(asUrgent);
  const today = itemsOf(sections, "today");
  const todayStarred = today.filter((i) => hasHack(i.title)).map(asUrgent);
  const todayNormal = today.filter((i) => !hasHack(i.title));
  const urgent = starFirst([...todayStarred, ...existingUrgent]);

  // Normal: existing normal + Today leftovers + all of This Week.
  const thisWeek = itemsOf(sections, "thisweek");
  const normal = [...itemsOf(sections, "normal"), ...todayNormal, ...thisWeek];

  const completed = itemsOf(sections, "completed");
  const deleted = itemsOf(sections, "deleted");

  // Preserve any unrecognized sections verbatim.
  const unknown = collect(sections, "unknown").map((s) => ({
    headerLine: s.headerLine,
    rawLines: s.rawLines ?? [],
  }));

  return { preamble, goals, top5, toread, urgent, normal, completed, deleted, unknown };
}
