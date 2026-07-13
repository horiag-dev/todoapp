// Parse a Big Rocks markdown todo document into a structured model.
//
// Design contract (Obsidian-safe): titles are stored VERBATIM — anything after
// the checkbox and the optional `⭐ ` star prefix is kept byte-for-byte, so
// `[[wikilinks]]`, `#tags`, and URLs round-trip losslessly. Tags are a derived
// read-only view (see tagsOf), never mutated out of the title.
//
// Non-owned regions (preamble/frontmatter, the Goals notepad, To Read, and any
// unrecognized section) are captured as raw lines and preserved verbatim by the
// serializer. Only the bucket sections we own are regenerated.

const STAR_RE = /^⭐️?[ \t]*/; // ⭐ optionally with a variation selector, then spaces
const TODO_RE = /^([ \t]*)- \[([ xX])\][ \t]*(.*)$/;
const HEADER_RE = /^(#{1,6})[ \t]+(.*\S)[ \t]*$/;

// Classify a section header by NAME (emoji-agnostic), most specific first.
// This is the parser-fallback fix: buckets are recognized by their word, not
// only by an emoji, so hand-typed or blank-template headers parse correctly.
export function classify(name) {
  const n = name.toLowerCase();
  if (n.includes("top 5")) return "top5";
  if (n.includes("goal")) return "goals";
  if (n.includes("big things")) return "bigthings";
  if (n.includes("to read")) return "toread";
  if (n.includes("today")) return "today";
  if (n.includes("this week")) return "thisweek";
  if (n.includes("urgent")) return "urgent";
  if (n.includes("normal") || n.includes("when there's time")) return "normal";
  if (n.includes("complet")) return "completed";
  if (n.includes("delet")) return "deleted";
  return "unknown";
}

const OWNED = new Set(["top5", "urgent", "normal", "completed", "deleted"]);
const MIGRATED = new Set(["today", "thisweek"]);
// kinds whose items we parse (owned buckets + the legacy ones we migrate away)
const PARSED = new Set([...OWNED, ...MIGRATED]);

function trimBlankEdges(lines) {
  let a = 0;
  let b = lines.length;
  while (a < b && lines[a].trim() === "") a++;
  while (b > a && lines[b - 1].trim() === "") b--;
  return lines.slice(a, b);
}

// Parse one bucket body into { items, strays }. A stray is a non-blank line that
// isn't a todo — preserved so nothing is silently dropped on rewrite.
function parseItems(bodyLines) {
  const items = [];
  const strays = [];
  for (const line of bodyLines) {
    if (line.trim() === "") continue;
    const m = TODO_RE.exec(line);
    if (!m) {
      strays.push(line);
      continue;
    }
    const checked = m[2].toLowerCase() === "x";
    let rest = m[3];
    const starred = STAR_RE.test(rest);
    if (starred) rest = rest.replace(STAR_RE, "");
    items.push({ checked, starred, title: rest });
  }
  return { items, strays };
}

export function parseVault(text) {
  const lines = text.split("\n");

  // Header line indices (any level). Everything before the first is preamble.
  const headerIdx = [];
  for (let i = 0; i < lines.length; i++) {
    if (HEADER_RE.test(lines[i]) && lines[i].startsWith("#")) headerIdx.push(i);
  }
  // Preamble = frontmatter + `# Todo List`, up to the first level-2/3 section.
  // A level-1 title is preamble, not a section, so find the first `##`+ header.
  let firstSection = headerIdx.find((i) => /^#{2,6}[ \t]/.test(lines[i]));
  if (firstSection === undefined) firstSection = lines.length;

  const preamble = trimBlankEdges(lines.slice(0, firstSection)).join("\n");

  // Walk section headers at level >= 2.
  const sectionHeaders = headerIdx.filter((i) => i >= firstSection);
  const sections = [];
  for (let s = 0; s < sectionHeaders.length; s++) {
    const hIdx = sectionHeaders[s];
    const nextIdx = sectionHeaders[s + 1] ?? lines.length;
    const headerLine = lines[hIdx];
    const name = HEADER_RE.exec(headerLine)[2];
    const kind = classify(name);
    const bodyLines = trimBlankEdges(lines.slice(hIdx + 1, nextIdx));

    const section = { kind, name, headerLine };
    if (PARSED.has(kind)) {
      const { items, strays } = parseItems(bodyLines);
      section.items = items;
      section.strays = strays;
    } else {
      // goals, toread, unknown → preserve verbatim
      section.rawLines = bodyLines;
    }
    sections.push(section);
  }

  return { preamble, sections };
}

// Derived, read-only tag view. Uses the " #tag" convention (a tag must be
// preceded by whitespace), which avoids matching URL fragments like
// `.../#/@user` and does not mutate the stored title.
export function tagsOf(title) {
  const out = [];
  const re = /(?:^|\s)#([A-Za-z0-9_/-]+)/g;
  let m;
  while ((m = re.exec(title)) !== null) out.push(m[1]);
  return out;
}

// Derived, read-only wikilink view.
export function linksOf(title) {
  const out = [];
  const re = /\[\[([^\]]+)\]\]/g;
  let m;
  while ((m = re.exec(title)) !== null) out.push(m[1]);
  return out;
}
