# Big Rocks First — Roadmap

> **Through-line:** the app's identity is *categorical priority + a weekly review cadence*, but the weekly review has been a value we **state**, not a flow we **have**. Most leverage below is turning machinery we already built (age ledger, draft/approve, Top 5, memory) into that ritual, and extending the assistant toward the vault north-star.

Status legend: **[building]** in progress · **[next]** queued · **[later]** · **[avoid]** fights a guardrail.

## Quick wins (hours each)

- **[done ✓ v0.5.0] Search everywhere** (S) — extend the `search` tool (was Urgent/Normal/Top 5 titles only) and UI filter to Goals, To Read, and Completed. Also strengthens dupe-detection, which couldn't see Completed.
- **[next] Live-reload on external edits** (S) — `fs.watch` the `.md` → push a refresh over the existing SSE channel instead of surfacing a hard conflict after the fact. Makes "edit in Obsidian anytime" feel true.
- **[done ✓ v0.6.0] To Read title unfurl** (S) — on `add_to_read`, fetch the page `<title>` and store `[Title](url)`. Bare URLs are why To Read rots; titles make de-staling doable. Best-effort, falls back to the raw URL.
- **[done ✓ v0.6.0] Quick-capture endpoint + Apple Shortcut** (S) — a dumb `POST /capture` (no agent in the path, so it never blocks on the API key) + a share-sheet Shortcut/Raycast snippet, reusing the server-side dupe check.
- **[done ✓ v0.8.0] Obsidian deep links** (S) — render `[[wikilinks]]` as `obsidian://open?...` links in todos, the memory modal, and the documents shelf. Cheapest bridge to the vault north-star.

## Medium bets (a day-ish)

- **[done ✓ v0.5.0] Guided Weekly Review + Big Rocks Check** (M) — *the headline.* A "Weekly Review" button runs a scripted agent flow: **recap what got done** (summarize Completed with detail — group by #tag/theme, name the meaningful ones) → reconcile last week's Top 5 (done / carry / drop) → sweep stale items via the age ledger (propose demote / delete / move-to-Goals) → de-stale To Read → propose next week's Top 5 → **Big Rocks Check** (compare the proposed five against the Goals notepad; flag any goal area none of them touches). Every mutation rides the existing per-change ✓/✗ draft surface; conversational, propose-and-confirm.
  - *User ask folded in:* the review explicitly reviews **all closed/completed items** and gives a specific recap (not just a count).
- **[done ✓ v0.7.0] "Plan my day" triage** (S/M) — daily counterpart: agent proposes today's "Today" set from Urgent + `age_days` + memory ("you said Fridays are for writing"), propose-and-confirm. First place Memory visibly pays off.
- **[next] PDF reading for the documents shelf** (S/M) — close the gap `read_document` admits; Claude reads PDFs natively as base64 `document` blocks.
- **[done ✓ v0.8.0] Urgent-integrity guard** (S) — when Urgent exceeds ~15, a once-a-week dismissible nudge ("when everything's urgent, nothing is — tidy?") that opens a curation draft. Defends the categorical model itself.
- **[later] Item notes** (M) — model indented lines under a todo as attached notes (click-to-expand, `append_note` tool). Long-lived Urgent items accumulate context that currently evaporates.

## Bigger bets / north-star

- **[done ✓ v0.8.0] Vault Module 2 — chat with your notes, read-only** (M/L) — `list_notes` / `read_note` / `search_vault` (ripgrep) against the existing `Vault` seam. Follow `[[wikilinks]]` from a todo into notes; cite notes as Obsidian deep links. Read-only = shippable without touching write-safety. *This is the north star.*
- **[later] Vault writes via draft/approve** (L) — extend preserve-and-splice + the ✓/✗ draft flow to arbitrary notes ("file these takeaways into [[Team Notes]]"). Never auto-apply to non-todo notes regardless of size — every note write is a reviewed draft.
- **[later] Review journal** (M) — the weekly review writes a short visible `reviews/…md` entry the user owns and browses in Obsidian. *Guardrail nuance:* the no-dates rule protects task metadata; a dated journal entry is a journal (Obsidian-native). Dates never touch `todo.md`. Decision pending.
- **[later] To Read graduation** (M/L) — when a To Read item is done, offer to fetch the page and draft a short literature note into the vault, link it, and remove the list entry. Turns To Read into a pipeline that feeds the vault.
- **[later] Connectors: Outlook + Slack capture** (L) — capture action items from mail/chat, scoped **narrowly** to *"this genuinely awaits your reply"* (not inbox triage — overwhelm is the failure mode). Design: a read-only classifier over Microsoft Graph / Slack that surfaces only high-confidence "awaiting your response" items; capture is **propose-and-confirm** into Urgent (dumb capture path, reuses dupe check); nothing auto-added. *Cost/caveats:* requires user-registered OAuth apps and the local service holding mail/chat tokens — a deliberate, security-reviewed module, built after the core review loop. "Reply to X" items are surfaced only if clearly awaiting the user; low-confidence noise is dropped, not shown.

## Explicitly avoid (fight the guardrails)

- **[avoid] Due dates / snooze / "remind me Tuesday."** Core violation (snooze is a date in a trenchcoat). Aligned substitute: a **"park it"** action that hides an item via the private ledger; the weekly review resurfaces it — cadence-based deferral, no date in the markdown.
- **[avoid] Recurring tasks.** Guardrailed until dates exist. Substitute: a memory bullet that lets the review *suggest* re-adding.
- **[avoid] Stats dashboards / streaks / karma.** Hold the line at a one-line review recap; a chart page makes the product optimize throughput over judgment.
- **[avoid] New buckets ("Someday" / custom / kanban).** Normal + age ledger + move-to-Goals already express "someday." Taxonomy creep is the slow death of categorical priority.
- **[avoid] Goal-project linking / multi-pane Goals editor.** The Big Rocks Check delivers goal-connectedness as a review-time nudge with zero UI machinery — that's the ceiling.
- **[avoid] Sync / mobile / cloud hosting.** Obsidian Sync / iCloud already solves multi-device for this audience; single-user loopback is the architecture.
- **[avoid] Autonomous background curation.** Crosses "AI assists, doesn't drive." All changes route through draft/approve while the user is present; the Urgent guard and the weekly review are the sanctioned shapes of proactivity.

---
*Roadmap drafted with Claude Fable 5, grounded in the v0.4.0 codebase. GitHub `enhancement` issues remain the canonical tracker; this file is the narrative.*
