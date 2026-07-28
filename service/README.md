# Big Rocks First — service

Local agent service over a markdown / Obsidian vault. Todos are Module 1; a
chat-with-your-notes assistant is the growth path. See the plan for the full
architecture.

**No API key, no cloud.** The vault `.md` file stays the source of truth on disk,
editable in any editor at any time. The agent (later phases) authenticates via
the `claude` CLI subscription login.

## Status

The service includes the deterministic Markdown core, a local web UI, and a
Claude Agent SDK assistant. Human edits save immediately. Assistant changes are
isolated in a reviewable draft and require Apply; external file changes are
detected with content versions so stale drafts cannot overwrite the vault.

- **Model** — Goals (notepad) · Urgent · Normal · Top 5. New captures default to Urgent.
- **The commitment ladder** — Urgent (could do) → `⭐` Today (intends to) → `‼️` Must
  (has committed to). Both live in Urgent and float to the top, Must above Today.
  Must is **capped at 3** and the cap is enforced, not advisory — it's what stops
  Must from quietly becoming a second Today. A Must is always also a Today; demoting
  one drops it back to Today rather than off the list. Musts never expire on a clock
  and never auto-roll-over: they're re-decided at the next plan-my-day. How long
  something has been a Must is kept in a private sidecar (`.bigrocks/must-since.json`),
  never as a date in the markdown, so the assistant can flag an item that's been
  "must do today" for a week.
- **Obsidian-safe writer** — preserve-and-splice: YAML frontmatter, `[[wikilinks]]`,
  and `#tags` round-trip byte-identical; only the bucket sections we own are
  regenerated. Titles are stored verbatim (tags/links are a derived read-only view).
- **Migration** (legacy → new, runs once): Today items with the `TODA[Yy]` hack →
  Urgent + starred (hack text cleaned); other Today → Normal; This Week → Normal;
  Completed/Deleted carried verbatim.
- **Persistence** — atomic write (temp + rename) + append-only history snapshots
  and a `log.jsonl` under `<vault>/.bigrocks/`.

### Layout

```
src/parse.mjs      markdown → model (verbatim titles; sections classified by name)
src/migrate.mjs    legacy → new model; TODAY-hack detection + cleaning
src/serialize.mjs  model → markdown (preserve-and-splice writer)
src/vault.mjs      Vault abstraction (vault dir + todo doc; load/save + history)
src/fsAtomic.mjs   atomic write helper
```

### Run

```sh
cd service
npm start                                       # then open http://127.0.0.1:5178
npm test                                        # unit + API + round-trip tests
npm run validate -- "/path/to/todo.md"          # migration report + checks against a real file
node scripts/migrate-file.mjs <src.md> <vaultDir>  # migrate a copy end-to-end (never touches src)
```

On first launch, use the native macOS file panel to open an existing Markdown
file or choose where to create a blank/demo file. Exact path entry remains
available as a fallback. You may instead set `TODO_FILE=/path/to/todo.md`
before starting the service.

The real-file test/validation defaults to `~/Downloads/new_worktodo 14.md`
(override with `REAL_TODO_FILE`).

### Deliver

Ships as a **plain Node service** — no app bundle, no installer (nothing for
Gatekeeper to flag, and it inherits your shell's environment, e.g. a
work-sanctioned `ANTHROPIC_API_KEY`).

```sh
sh scripts/build-service-package.sh    # → dist/big-rocks-first-service-<version>.tar.gz (+ .sha256)
```

To run a delivered package: extract it and `sh run.sh` from a Terminal, then open
`http://127.0.0.1:5178`. `run.sh` installs locked deps on first run (Node 18+),
then `node src/server.mjs`. Set `PORT=5179 sh run.sh` to change the port. For a
Dock icon, use Chrome's "Save and Share → Create Shortcut" (a web manifest + PNG
icons are served).

### Capture (share sheet / Shortcut / curl)

A dumb, agent-free endpoint for fast capture into Urgent — no API key required:

```sh
curl -s -X POST http://127.0.0.1:5178/api/capture \
  -H 'content-type: application/json' -d '{"title":"Buy milk"}'
# -> {"ok":true,"captured":true,"bucket":"urgent","duplicateOf":null}
```

Pass `"bucket":"normal"` to land it in Normal instead. `duplicateOf` is the title
of a near-duplicate already on your list (the item is still captured — the caller
decides what to do). Wrap it in a macOS **Shortcut** ("Get Contents of URL" → POST
JSON) on the share sheet for one-tap capture from anywhere. Bare URLs added to
**To Read** are unfurled to a `[Page Title](url)` link automatically.

## Safety model

- The server binds to loopback only.
- Unknown sections, frontmatter, wikilinks, and tags are preserved.
- Every write snapshots the previous file under `.bigrocks/history/`.
- Direct edits are blocked while an assistant draft is pending.
- Apply uses optimistic concurrency and fails if the file changed externally.
- Assistant memory is a visible `Assistant Memory.md` note you own and edit; the
  agent reads it each turn and edits one bullet at a time (never secrets or dates;
  provenance/staleness live privately under `.bigrocks/memory-meta.json`). It is
  background context, never authority — your current message always wins.
