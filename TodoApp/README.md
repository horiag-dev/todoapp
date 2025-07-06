# Todo App

A simple macOS application to manage your todo list with AI-powered refactoring and tag suggestions.

## Features

- Add new todos
- Mark todos as complete/incomplete
- Delete todos
- Todos are automatically saved and persist between app launches
- **NEW: AI-powered todo refactoring** - Automatically improve todo titles and suggest relevant tags
- **NEW: Smart tag suggestions** - Get contextual tag recommendations based on todo content
- **NEW: Priority optimization** - AI suggests appropriate priority levels for your todos

## AI Integration

The app now includes OpenAI integration to help you create better, more actionable todos:

### How to Set Up AI Features

1. **Get an OpenAI API Key:**
   - Go to https://platform.openai.com/api-keys
   - Sign in or create an account
   - Click "Create new secret key"
   - Copy the key (starts with "sk-")

2. **Configure in the App:**
   - Click the gear icon (⚙️) in the top-right corner
   - Paste your API key in the "OpenAI API Configuration" section
   - Click "Save API Key"
   - Optionally test the connection

### Using AI Refactoring

1. **Type a todo** in the input field
2. **Click the magic wand** (🪄) button next to the input field
3. **Review AI suggestions** - the app will show:
   - Refactored title (more actionable and clear)
   - Suggested tags (based on content and existing tags)
   - Recommended priority level
4. **Apply suggestions** or dismiss them

### Example

**Original:** "meeting with john"
**AI Refactored:** "Schedule follow-up meeting with John to discuss project timeline"
**Suggested Tags:** ["meetings", "john", "project"]
**Priority:** Normal

## How to Use

1. Open the project in Xcode
2. Build and run the application
3. To add a new todo:
   - Type your todo in the text field at the top
   - Click the plus button or press Enter
   - For AI enhancement, click the magic wand button first
4. To mark a todo as complete:
   - Click the circle button next to the todo
5. To delete a todo:
   - Click the trash icon next to the todo

## Requirements

- macOS 11.0 or later
- Xcode 13.0 or later
- OpenAI API key (for AI features)

## Privacy & Security

- Your OpenAI API key is stored locally in UserDefaults
- Todo content is sent to OpenAI for processing
- No data is stored on OpenAI servers beyond the immediate request
- You can disable AI features by not setting an API key

## Backup System

The app automatically creates backups every 3 hours in the app's documents directory:
```
~/Library/Containers/Horia.TodoApp/Data/Documents/TodoAppBackups/
``` 