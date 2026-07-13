# Big Rocks First — service

Local agent service over a markdown / Obsidian vault. Todos are Module 1; a
chat-with-your-notes assistant is the growth path. See the plan for the full
architecture.

**No API key, no cloud.** The vault `.md` file stays the source of truth on disk,
editable in any editor at any time. The agent (later phases) authenticates via
the `claude` CLI subscription login.

## Status — Phase 0 (this commit): parser / writer / migration, no agent

The deterministic, non-agent core that safely reads and rewrites the vault file.
Everything the agent will do later is proposed against an in-memory model and
persisted through this layer.

- **Model** — Goals (notepad) · Urgent (with a `⭐` star = "very urgent") · Normal ·
  Top 5. Order within Urgent is line position. New captures will default to Urgent.
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
npm test                                        # unit + round-trip + real-file (if present)
npm run validate -- "/path/to/todo.md"          # migration report + checks against a real file
node scripts/migrate-file.mjs <src.md> <vaultDir>  # migrate a copy end-to-end (never touches src)
```

The real-file test/validation defaults to `~/Downloads/new_worktodo 14.md`
(override with `REAL_TODO_FILE`).

## Next

- **Phase 1** — the `@anthropic-ai/claude-agent-sdk` `query()` loop with gated
  read tools + `add_todo`/`complete`, SSE background job, minimal chat UI; register
  the dormant tier-2 vault-read capability (disabled) as the seam for the note assistant.
