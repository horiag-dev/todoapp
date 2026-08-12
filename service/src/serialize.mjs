// Serialize the model back to markdown — the preserve-and-splice writer.
//
// Owned bucket sections (Top 5, Urgent, Normal, Completed, Deleted) are
// regenerated with canonical headers. Everything else — the preamble/frontmatter,
// the Goals notepad, To Read, and any unrecognized section — is emitted from its
// captured raw lines, so it round-trips verbatim.

const HEADERS = {
  top5: "### 🔴 Top 5 of the week",
  urgent: "### 🔴 Urgent",
  normal: "### 🔵 Normal",
  parked: "### 💤 Parked",
  completed: "### ✅ Completed",
  deleted: "### 🗑️ Deleted",
};

function renderItem(it) {
  const box = it.checked ? "x" : " ";
  // One marker only. `↳ ` (queued behind the line above) outranks both, since a
  // blocked item can't be an intention; `‼️ ` (Must) already implies Today, so it
  // replaces the star rather than stacking with it.
  const mark = it.blocked ? "↳ " : it.must ? "‼️ " : it.starred ? "⭐ " : "";
  return `- [${box}] ${mark}${it.title}`;
}

// A section is `header`, a blank line, then the body — or just the header when
// the body is empty.
function block(header, bodyLines) {
  const body = bodyLines.filter((l, i, a) => !(l === "" && (i === 0 || i === a.length - 1)));
  return body.length ? `${header}\n\n${body.join("\n")}` : header;
}

function rawBlock(section) {
  return section ? block(section.headerLine, section.rawLines) : null;
}

export function serialize(model) {
  const blocks = [];

  if (model.preamble && model.preamble.trim() !== "") blocks.push(model.preamble);

  const goals = rawBlock(model.goals);
  if (goals) blocks.push(goals);

  blocks.push(block(HEADERS.top5, model.top5.map(renderItem)));

  const bigthings = rawBlock(model.bigthings);
  if (bigthings) blocks.push(bigthings);

  const toread = rawBlock(model.toread);
  if (toread) blocks.push(toread);

  blocks.push(block(HEADERS.urgent, model.urgent.map(renderItem)));
  blocks.push(block(HEADERS.normal, model.normal.map(renderItem)));
  // Parked is emitted only when non-empty, so files without it round-trip untouched.
  if (model.parked?.length) blocks.push(block(HEADERS.parked, model.parked.map(renderItem)));
  blocks.push(block(HEADERS.completed, model.completed.map(renderItem)));
  blocks.push(block(HEADERS.deleted, model.deleted.map(renderItem)));

  for (const u of model.unknown ?? []) blocks.push(block(u.headerLine, u.rawLines));

  return blocks.join("\n\n") + "\n";
}
