// Persistent assistant memory: a visible "Assistant Memory.md" note in the vault
// that the agent reads every turn and edits one bullet at a time. Provenance and
// staleness live privately in .bigrocks/memory-meta.json so the note stays clean
// and date-free (the no-dates guardrail holds). Edits are line-level splices that
// preserve any prose / sub-bullets the user wrote — the same philosophy as the
// Goals writer, but one bullet at a time so agent and human edits coexist safely.
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { keyOf } from "./ledger.mjs";
import { writeFileAtomic } from "./fsAtomic.mjs";

export const MEMORY_BASENAME = "Assistant Memory.md";
export const SECTIONS = ["How I should behave", "About you & your work", "Themes & projects", "Working notes"];
export const LIMITS = { bulletChars: 140, totalBullets: 60, workingNotes: 15, injectChars: 3500 };

const INTRO = "*Notes the Big Rocks assistant keeps about how you work. It reads this before every chat. Edit or delete anything — it's your file.*";
const SCAFFOLD = `# Assistant Memory\n\n${INTRO}\n\n${SECTIONS.map((s) => `## ${s}\n`).join("\n")}`;

const SECRET_RE = /\b(sk-[A-Za-z0-9]{8,}|api[_-]?key|password|passwd|secret|token)\b|\b\d{13,}\b/i;
const DATE_RE = /\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}\/\d{1,2}\/\d{2,4}\b/;

const isBullet = (line) => /^- \S/.test(line);
const bulletText = (line) => line.replace(/^-\s+/, "").trim();

const metaPath = (vault) => join(vault.machineDir, "memory-meta.json");
const loadMeta = (vault) => { try { return JSON.parse(readFileSync(metaPath(vault), "utf8")); } catch { return {}; } };
const saveMeta = (vault, meta) => { mkdirSync(vault.machineDir, { recursive: true }); writeFileSync(metaPath(vault), JSON.stringify(meta), "utf8"); };
const readRaw = (vault) => { try { return readFileSync(vault.memoryPath, "utf8"); } catch { return ""; } };

function snapshot(vault) {
  if (!existsSync(vault.memoryPath)) return;
  const dir = join(vault.machineDir, "memory-history");
  mkdirSync(dir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, "-");
  copyFileSync(vault.memoryPath, join(dir, `${ts}.md`));
  try {
    const snaps = readdirSync(dir).filter((f) => f.endsWith(".md")).sort();
    for (const old of snaps.slice(0, -20)) rmSync(join(dir, old), { force: true });
  } catch {}
}

// Parse into a lines array plus the known sections and their bullet positions.
function parse(raw) {
  const lines = raw.replace(/\r/g, "").split("\n");
  const sections = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^##\s+(.+?)\s*$/);
    if (m) sections.push({ name: m[1].trim(), headerIdx: i, endIdx: lines.length });
  }
  for (let i = 0; i < sections.length; i++) sections[i].endIdx = i + 1 < sections.length ? sections[i + 1].headerIdx : lines.length;
  return { lines, sections };
}
const sectionNamed = (sections, name) => sections.find((s) => s.name === name);
function bulletsIn(lines, sec) {
  const out = [];
  for (let i = sec.headerIdx + 1; i < sec.endIdx; i++) if (isBullet(lines[i])) out.push({ idx: i, text: bulletText(lines[i]) });
  return out;
}
function managedBullets(lines, sections) {
  const out = [];
  for (const sec of sections) if (SECTIONS.includes(sec.name)) for (const b of bulletsIn(lines, sec)) out.push({ ...b, section: sec.name });
  return out;
}

// Load the note + sweep the sidecar: stamp user-typed bullets as "user-edited",
// drop meta whose bullet the user has deleted. Mirrors ledger.mjs's touch().
export function loadMemory(vault) {
  const raw = readRaw(vault);
  const { lines, sections } = parse(raw);
  const bullets = managedBullets(lines, sections);
  const meta = loadMeta(vault);
  const now = new Date().toISOString();
  const live = new Set(bullets.map((b) => keyOf(b.text)));
  let changed = false;
  for (const b of bullets) { const k = keyOf(b.text); if (!meta[k]) { meta[k] = { firstSeen: now, lastConfirmed: now, source: "user-edited" }; changed = true; } }
  for (const k of Object.keys(meta)) if (!live.has(k)) { delete meta[k]; changed = true; }
  if (changed) saveMeta(vault, meta);
  const withMeta = bullets.map((b) => {
    const m = meta[keyOf(b.text)] || {};
    return { ...b, source: m.source, ageDays: m.lastConfirmed ? Math.floor((Date.now() - Date.parse(m.lastConfirmed)) / 86400000) : null };
  });
  return { raw, lines, sections, bullets: withMeta };
}

const guard = (text) => {
  if (!text) return "Nothing to remember.";
  if (SECRET_RE.test(text)) return "That looks like a secret or credential — not storing it.";
  if (DATE_RE.test(text)) return "Memory stays date-free (the app is categorical, not temporal). Rephrase without the date.";
  if (text.length > LIMITS.bulletChars) return `Too long (${text.length} chars) — keep memory bullets under ${LIMITS.bulletChars}. Shorten it.`;
  return null;
};

function appendBullet(vault, section, text, extra = {}) {
  text = String(text ?? "").trim();
  if (!SECTIONS.includes(section)) return `Unknown section "${section}". Use one of: ${SECTIONS.join(", ")}.`;
  const bad = guard(text);
  if (bad) return bad;
  const { bullets } = loadMemory(vault);
  const key = keyOf(text);
  if (bullets.some((b) => keyOf(b.text) === key)) return `Already remembered: "${text}".`;
  if (bullets.length >= LIMITS.totalBullets) return `Memory is full (${LIMITS.totalBullets} notes) — consolidate or forget something first.`;
  if (section === "Working notes" && bullets.filter((b) => b.section === "Working notes").length >= LIMITS.workingNotes)
    return `Working notes is full (${LIMITS.workingNotes}) — promote or drop some first.`;

  const raw = existsSync(vault.memoryPath) ? readRaw(vault) : SCAFFOLD;
  const seed = parse(raw);
  const lines = seed.lines;
  if (!sectionNamed(seed.sections, section)) {
    if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("");
    lines.push(`## ${section}`, "");
  }
  const re = parse(lines.join("\n"));
  const sec = sectionNamed(re.sections, section);
  // Insert after the last non-blank line of the section, so we land after any
  // existing bullets / prose / sub-bullets the user wrote (never between them).
  let at = sec.headerIdx + 1;
  for (let i = sec.headerIdx + 1; i < sec.endIdx; i++) if (re.lines[i].trim() !== "") at = i + 1;
  re.lines.splice(at, 0, `- ${text}`);
  snapshot(vault);
  writeFileAtomic(vault.memoryPath, re.lines.join("\n"));
  const meta = loadMeta(vault);
  const now = new Date().toISOString();
  meta[key] = { firstSeen: now, lastConfirmed: now, source: extra.source || "user-said", ...(extra.why ? { why: extra.why } : {}) };
  saveMeta(vault, meta);
  return `Remembered under "${section}".`;
}

const uniqueMatch = (bullets, match) => {
  const m = String(match ?? "").toLowerCase().trim();
  if (!m) return { error: "Provide text that identifies the memory." };
  const hits = bullets.filter((b) => b.text.toLowerCase().includes(m));
  if (hits.length === 0) return { error: `No memory matches "${match}".` };
  if (hits.length > 1) return { error: `"${match}" matches ${hits.length} memories — be more specific.` };
  return { hit: hits[0] };
};

function replaceBullet(vault, match, text, extra = {}) {
  text = String(text ?? "").trim();
  const bad = guard(text);
  if (bad) return bad;
  const { lines, bullets } = loadMemory(vault);
  const { hit, error } = uniqueMatch(bullets, match);
  if (error) return error;
  const L = [...lines];
  L[hit.idx] = `- ${text}`;
  snapshot(vault);
  writeFileAtomic(vault.memoryPath, L.join("\n"));
  const meta = loadMeta(vault);
  const now = new Date().toISOString();
  const prev = meta[keyOf(hit.text)] || { firstSeen: now, source: "user-said" };
  delete meta[keyOf(hit.text)];
  meta[keyOf(text)] = { ...prev, lastConfirmed: now, ...(extra.why ? { why: extra.why } : {}) };
  saveMeta(vault, meta);
  return `Updated to: "${text}".`;
}

function removeBullet(vault, match) {
  const { lines, bullets } = loadMemory(vault);
  const { hit, error } = uniqueMatch(bullets, match);
  if (error) return error;
  const L = [...lines];
  L.splice(hit.idx, 1);
  snapshot(vault);
  writeFileAtomic(vault.memoryPath, L.join("\n"));
  const meta = loadMeta(vault);
  delete meta[keyOf(hit.text)];
  saveMeta(vault, meta);
  return `Forgotten: "${hit.text}".`;
}

function readAnnotated(vault) {
  const { raw, bullets } = loadMemory(vault);
  if (!raw.trim()) return "Assistant Memory is empty. Use `remember` to add a durable note when the user states a lasting preference.";
  const stale = bullets.filter((b) => b.ageDays != null && b.ageDays >= 30);
  let out = raw.trimEnd();
  if (stale.length) out += "\n\n---\nStaleness (not confirmed in 30+ days):\n" + stale.map((b) => `- "${b.text}" — ${b.ageDays}d`).join("\n");
  return out;
}

// Full-file injection with a hard char budget; over budget we trim Working notes
// (the churny, least-durable section) from the end first.
export function injectionText(vault) {
  const { bullets } = loadMemory(vault);
  if (!bullets.length) return "";
  const bySection = {};
  for (const b of bullets) (bySection[b.section] ||= []).push(b.text);
  const render = (workingCap) => {
    let out = "";
    for (const sec of SECTIONS) {
      const all = bySection[sec] || [];
      const items = sec === "Working notes" && workingCap != null ? all.slice(0, workingCap) : all;
      if (!items.length) continue;
      out += `## ${sec}\n` + items.map((t) => `- ${t}`).join("\n") + "\n";
      if (sec === "Working notes" && workingCap != null && workingCap < all.length) out += `…(${all.length - workingCap} more — read_memory)\n`;
      out += "\n";
    }
    return out.trim();
  };
  const full = render(null);
  if (full.length <= LIMITS.injectChars) return full;
  const total = (bySection["Working notes"] || []).length;
  for (let w = total - 1; w >= 0; w--) { const r = render(w); if (r.length <= LIMITS.injectChars) return r; }
  return render(0);
}

// Facade bound to a vault — threaded into the agent like `docs`.
export function createMemory(vault) {
  return {
    injectionText: () => injectionText(vault),
    readAnnotated: () => readAnnotated(vault),
    append: (section, text, extra) => appendBullet(vault, section, text, extra),
    replace: (match, text, extra) => replaceBullet(vault, match, text, extra),
    remove: (match) => removeBullet(vault, match),
    read: () => ({ content: readRaw(vault), exists: existsSync(vault.memoryPath), path: vault.memoryPath }),
  };
}
