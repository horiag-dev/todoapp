# Big Rocks First — product direction

A markdown-file-backed macOS todo app built around **categorical priority** (Today / Urgent / This Week / Normal) and a **weekly review cadence**, with AI-assisted auto-tagging and review.

## Differentiator (don't dilute)

- **Markdown is the source of truth.** Users own their data; the app is a view over a `.md` file.
- **Priority is categorical, not temporal.** Buckets, not dates. The weekly review is when planning happens.
- **AI assists, doesn't drive.** Auto-tagging and weekly summaries are nudges, not authority.

## Product guardrails (things we explicitly don't do)

- **No due-date / calendar system.** Things 3 and Todoist already own that space. Adding dates would erode the "categorical priority + weekly cadence" identity and pull us into a feature race we can't win.
- **No recurring tasks** until / unless dates land — they require a temporal model the app doesn't have.
- **No stats / streaks / karma as core features.** Fine as small affordances, never as a primary surface.
- **No multi-pane editor for goals.** Goals are a notepad, not a project tool — keep the editor simple even if the rendered view stays rich.

## Roadmap

Open improvements live as GitHub issues with the `enhancement` label:
<https://github.com/horiag-dev/todoapp/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement>

When picking one up, check it still aligns with the guardrails above before starting.
