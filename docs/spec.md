# Big Rocks First — Product Specification

## Overview

**Big Rocks First** is a macOS productivity app that helps users prioritize what matters most. It uses a "big rocks" metaphor — focus on the large, important tasks first, and the smaller ones fit around them.

All data is stored as human-readable Markdown files the user controls.

## Target Users

- Professionals managing multiple projects and priorities
- People who want a simple, file-based task system (no cloud lock-in)
- Users who value the "big rocks first" prioritization framework

## Core Concepts

### Priority Levels (highest to lowest)
| Priority | Emoji | Use Case |
|----------|-------|----------|
| Today | ☀️ | Tasks to focus on right now |
| This Week | 🟠 | Tasks to complete this week (default) |
| Urgent | 🔴 | Needs attention soon |
| Normal | 🔵 | Backlog / eventually |

### Context Tags
Customizable tags that describe **how** you'll work on a task:
- `#prep` — Preparation work
- `#reply` — Respond to someone
- `#deep` — Deep focus work
- `#waiting` — Blocked / waiting on someone

Users can add, rename, and remove context tags in Settings.

### Goals & Big Things
- **Goals** — Freeform markdown notepad with optional `#tag` links to connect goals to tasks
- **Big Things for the Week** — Numbered list of 1-3 high-level outcomes for the week
- **Top 5 of the Week** — The 5 most important individual tasks, pinned at the top

## Features

### Task Management
- Create, edit, complete, delete, and restore todos
- Assign priority level and context tags
- Drag-reorder Top 5 tasks
- Filter/group by priority, context, or tag
- Bulk action: move all completed to deleted

### Mind Map
- Visual graph of goals → tags → todos
- Pan, zoom, and interact with nodes
- Auto-layout based on tag relationships

### Quick Add (⌘⇧T)
- Global hotkey opens a floating panel from any app
- Add task with title, context tag, and additional tags
- Panel dismisses after adding

### AI Features (Optional)
- **Auto-tag** — Right-click a todo to get AI-suggested context tags
- **Weekly Review** — AI analyzes todos and goals, suggests rephrasing, re-prioritization, and tag changes
- Powered by Claude API (user provides their own key)
- **Demo mode** — Keyword-based suggestions with no API calls

### File Management
- Open existing `.md` files or create new ones (blank or demo)
- Auto-save with 500ms debounce
- Automatic backups every 3 hours to `~/Documents/TodoAppBackups/`
- Remembers last opened file

### Appearance
- Dark / Light / System theme modes
- Custom accent colors via Theme system

## Markdown File Format

The `.md` file is the single source of truth. Format:

```markdown
## 🎯 Goals
Freeform markdown with #tags

### 🔴 Top 5 of the week
- [ ] Task #tag1 #tag2

## 📋 Big Things for the Week
1. Big thing description

### ☀️ Today
- [ ] Task #tag

### 🟠 This Week
- [ ] Task #tag

### 🔴 Urgent
- [ ] Task #tag

### 🔵 Normal
- [ ] Task #tag

### ✅ Completed
- [x] Task #tag

### 🗑️ Deleted
- [ ] Task #tag
```

### Parsing Rules
- `- [ ]` = incomplete, `- [x]` = completed
- Tags are space-separated after the title: `Title #tag1 #tag2`
- `#today` tag in non-Today sections migrates the todo to Today priority
- Section headers determine priority assignment on load
- Goals section supports arbitrary markdown (bold, lists, etc.)

## Non-Functional Requirements

- **Platform:** macOS 15.4+
- **Framework:** SwiftUI + AppKit (for panels, hotkeys, menus)
- **Storage:** Local filesystem only (no cloud sync built in)
- **Security:** API keys stored in macOS Keychain
- **Privacy:** Demo mode is fully offline; live mode sends only todo text to Anthropic API
- **Performance:** Cached tag/mind-map computations with hash-based invalidation; debounced saves

## Out of Scope (Current Version)
- iOS / iPadOS / visionOS
- Cloud sync or collaboration
- Recurring / repeating tasks
- Due dates or calendar integration
- Subtasks / task hierarchy
- File encryption
