# Big Rocks First

A macOS productivity app for managing todos with priorities, context tags, goals, and an optional AI-powered auto-tagging feature.

## Quick Start

1. Open `TodoApp.xcodeproj` in Xcode
2. Build and run (Cmd+R)
3. The app opens a file picker — create a new `.md` file or open an existing one

## Demo Mode (AI Feature)

The app has an optional AI feature that auto-suggests context tags for your todos. To try it without a real API key:

1. Open **Settings** (gear icon)
2. In the **Claude API Key** field, type `demo`
3. Click **Save**

That's it. Now right-click any todo and choose **"Auto-tag with AI"** — the app will suggest a context tag based on the todo's text. Demo mode uses keyword matching to simulate the AI response.

To use the real AI feature instead, replace `demo` with a real API key from [console.anthropic.com](https://console.anthropic.com/).

## Features

- **Priorities** — Organize todos by This Week, Urgent, and Normal
- **Top 5 of the Week** — Pin your most important tasks
- **Context Tags** — Categorize by context (prep, reply, deep work, waiting)
- **Custom Tags** — Create and manage your own tags
- **Goals & Big Things** — Markdown notepad for goals with tag linking
- **Mind Map** — Visual overview of your goals and todos by tag
- **Quick Add** — Global hotkey (Cmd+Shift+T) to add todos from anywhere
- **Auto-tag with AI** — Optional Claude-powered context suggestions
- **Dark/Light/System themes**
- **Markdown file storage** — Your data is a plain `.md` file you own

## AI Auto-Tagging

When enabled, right-clicking a todo shows an **"Auto-tag with AI"** option that analyzes the todo text and suggests one of your configured context tags.

| Mode | How it works |
|------|-------------|
| **Demo** (`demo` key) | Keyword matching, no network calls, works offline |
| **Live** (real API key) | Calls Claude API for intelligent categorization |

## How to Use

- **Add a todo**: Click "+" or use the input field at the top
- **Set priority**: Right-click a todo > Priority
- **Add tags**: Right-click a todo > Tags or Context
- **AI auto-tag**: Right-click a todo > Auto-tag with AI (requires API key or demo mode)
- **Edit a todo**: Double-click on its title
- **Quick Add**: Press Cmd+Shift+T from anywhere (requires accessibility permission)
- **Mind Map**: Toggle the mind map view from the toolbar

## Requirements

- macOS 15.4 or later
- Xcode 16.3 or later

## Privacy & Security

- Your API key is stored in the macOS Keychain (not UserDefaults)
- In demo mode, no data leaves your device
- In live mode, only the todo text is sent to the Anthropic API for categorization
- All todo data is stored locally in a `.md` file you choose

## Backups

The app creates automatic backups every 3 hours at:
```
~/Documents/TodoAppBackups/
```
