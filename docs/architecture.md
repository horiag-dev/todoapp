# Big Rocks First — Architecture

## High-Level Architecture

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Views                     │
│  TodoListView · TodoItemView · MindMapView · etc.   │
├─────────────────────────────────────────────────────┤
│                  TodoList (ViewModel)                │
│  @Published state · CRUD operations · save/load     │
├─────────────────────────────────────────────────────┤
│              Markdown Persistence Layer              │
│  performSave() · loadTodos() · formatTodo()         │
├──────────────┬──────────────────────────────────────┤
│  AI Services │        Singletons / Managers          │
│  Claude API  │  APIKeyManager · AppearanceManager   │
│  Weekly Rev. │  ContextConfigManager · HotkeyMgr    │
└──────────────┴──────────────────────────────────────┘
         │                       │
    Anthropic API          macOS Keychain
    (optional)             + UserDefaults
```

## Module Breakdown

### Core (3 files)
| File | Responsibility |
|------|---------------|
| `Todo.swift` | Data model: `Todo` struct, `Priority` enum |
| `TodoList.swift` | Central data store (ObservableObject), markdown I/O, CRUD |
| `TodoApp.swift` | `@main` entry, window/menu bar setup |

### Views (7 files)
| File | Responsibility |
|------|---------------|
| `TodoListView.swift` | Main view (~2800 lines) — sections, goals, filtering, grouping |
| `TodoItemView.swift` | Single todo row with checkbox, tags, context menu |
| `NewTodoView.swift` | Modal for creating a new todo |
| `WalkthroughView.swift` | First-run onboarding tutorial |
| `WeeklyReviewView.swift` | AI weekly review UI with accept/reject suggestions |
| `TagView.swift` | Tag pills, tag cloud, interactive tag selection |
| `FlowLayout.swift` | Custom SwiftUI `Layout` for wrapping tag pills |

### Mind Map (8 files)
| File | Responsibility |
|------|---------------|
| `MindMapView.swift` | Container view with controls |
| `MindMapCanvas.swift` | Rendering canvas (pan/zoom) |
| `MindMapDataBuilder.swift` | Builds node tree from goals + todos |
| `MindMapLayout.swift` | Hierarchical layout algorithm |
| `MindMapModels.swift` | `MindMapNode`, `MindMapChildNode`, `MindMapGoalItem` |
| `MindMapNodeViews.swift` | Visual node components |
| `MindMapControls.swift` | Zoom/reset controls |
| `ConnectionLine.swift` | Bezier connection rendering |

### Settings (4 files)
| File | Responsibility |
|------|---------------|
| `SettingsView.swift` | Settings UI (appearance, API key, context tags) |
| `APIKeyManager.swift` | Keychain read/write for Claude API key |
| `AppearanceManager.swift` | Dark/light/system mode persistence |
| `ContextConfiguration.swift` | User-configurable context tags (CRUD + persistence) |

### Services (2 files)
| File | Responsibility |
|------|---------------|
| `ClaudeCategorizationService.swift` | AI auto-tagging via Claude API |
| `WeeklyReviewService.swift` | AI weekly review via Claude API |

### Utilities (2 files)
| File | Responsibility |
|------|---------------|
| `Theme.swift` | Colors, fonts, shadows, animation constants |
| `GlobalHotkeyManager.swift` | ⌘⇧T global hotkey via Carbon HIToolbox |

### Quick Add (1 file)
| File | Responsibility |
|------|---------------|
| `QuickAddPanel.swift` | Floating `NSPanel` + SwiftUI content for global quick-add |

## Data Flow

### State Management
```
TodoList (@ObservableObject)
  ├── @Published todos: [Todo]
  ├── @Published top5Todos: [Todo]
  ├── @Published deletedTodos: [Todo]
  ├── @Published goals: String
  ├── @Published bigThings: [String]
  └── Cached: allTags, mindMapNodes (hash-invalidated)
       │
       ▼
  Views observe via @ObservedObject / @EnvironmentObject
```

### Save Pipeline
```
User action → CRUD method → saveTodos()
  → Cancel pending DispatchWorkItem
  → Create new work item capturing current state
  → Schedule on main after 500ms debounce
  → Execute on background (utility QoS) queue
  → performSave() writes markdown to disk
```

### Load Pipeline
```
File selected → loadTodos()
  → Read file as String
  → Line-by-line parsing with section state machine
  → Section headers (## / ###) set flags: isInGoalsSection, isInTodaySection, etc.
  → Todo lines (- [ ]) parsed into Todo structs
  → Tags extracted from " #tag" suffixes
  → #today tag migrated to .today priority
  → State assigned to @Published properties
```

## Key Design Decisions

### 1. Markdown as Storage
- **Why:** Human-readable, version-controllable, no vendor lock-in
- **Trade-off:** No structured queries, section-based parsing is fragile
- **Mitigation:** Strict section ordering, automatic backups

### 2. Single ViewModel (TodoList)
- **Why:** Simple app with one primary data set; avoids over-engineering
- **Trade-off:** TodoList.swift is a large file mixing I/O and business logic
- **Future:** Could extract `MarkdownParser` and `MarkdownWriter` for testability

### 3. Singletons for Managers
- **Why:** Global settings (appearance, API key, context config) need app-wide access
- **Trade-off:** Hard to test in isolation, implicit dependencies
- **Mitigation:** Managers are small and focused

### 4. Debounced Saves
- **Why:** Many rapid edits (typing, reordering) shouldn't each trigger disk I/O
- **Implementation:** 500ms `DispatchWorkItem` on main, executed on background queue
- **Note:** State is captured at scheduling time to avoid race conditions

### 5. Hash-Based Cache Invalidation
- **Why:** `allTags` and `mindMapNodes` are expensive to recompute
- **Implementation:** `Hasher` combines todo IDs, tags, and completion state; cache is valid if hash matches

### 6. Optional AI Integration
- **Why:** AI features are valuable but shouldn't be required
- **Implementation:** Demo mode uses keyword matching; live mode calls Claude API
- **Security:** API key in Keychain, never logged or persisted elsewhere

## Dependencies

**Zero external dependencies.** The app uses only Apple frameworks:
- SwiftUI, AppKit, Foundation, Combine
- Security (Keychain), UniformTypeIdentifiers
- Carbon.HIToolbox (global hotkeys)

## Build & Distribution

- **Min deployment:** macOS 15.4
- **Xcode:** 16.3+
- **Targets:** TodoApp, TodoAppTests, TodoAppUITests
- **Distribution:** App Store (accepted Feb 2026)
- **No CI/CD** — manual builds and archive

## Known Architectural Debt

1. **TodoListView.swift is ~2800 lines** — Could be broken into smaller views/view models
2. **TodoList mixes concerns** — CRUD, markdown I/O, file management, and backup logic in one class
3. **No protocol abstractions** — Services and managers are concrete types, making testing harder
4. **Test coverage is minimal** — Only basic tag and CRUD tests exist; no markdown parsing or save/load tests
5. **Existing test signatures may not match** — `addTag(_:to:)` in tests vs `addTag(to:tag:)` in source
