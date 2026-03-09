# Big Rocks First — Improvements Tracker

## How to use this document
Work through items top-to-bottom. Each item is independent unless noted. Check the box when done.

---

## P0 — Bugs & Data Safety

- [x] **1. Replace `fatalError` in TodoList init**
  `TodoList.swift:53` — App crashes if Documents directory is inaccessible. Replace with graceful error handling.
  *Fixed: Falls back to `temporaryDirectory` instead of crashing.*

- [x] **2. Silent file write failures → notify user**
  `TodoList.swift:573` — `performSave()` catches write errors and discards them. User loses data with no feedback. Show an alert or status indicator on failure.
  *Fixed: Added `@Published lastSaveError` + red banner with Retry button in TodoListView.*

- [x] **3. Save ordering not guaranteed**
  `TodoList.swift:449-451` — Debounced saves dispatch to a background queue without ordering. Rapid edits could cause an older save to overwrite a newer one. Use a serial queue.
  *Fixed: Replaced `DispatchQueue.global` with a dedicated serial `saveQueue`.*

---

## P1 — Code Duplication & Maintainability

- [ ] **4. Extract "refresh todo after mutation" helper**
  `TodoItemView.swift` — The pattern below appears **11 times**:
  ```swift
  if isTop5 {
      if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
          self.todo = updated
      }
  } else {
      if let updated = todoList.todos.first(where: { $0.id == todo.id }) {
          self.todo = updated
      }
  }
  ```
  Extract into a single `refreshTodo()` method.

- [ ] **5. Duplicate `linkDetector` static**
  `Todo.swift:51` and `TodoItemView.swift:110` both declare identical `NSDataDetector` statics. Keep only the one in `Todo.swift` and reference `todo.containsLinks` from the view.

- [ ] **6. Break up TodoListView.swift (~2800 lines)**
  Extract into separate files:
  - `GoalsSectionView.swift` — goals editing
  - `BigThingsSectionView.swift` — big things list
  - `Top5SectionView.swift` — top 5 section + drag reorder
  - `TodoSectionView.swift` — priority-grouped todo sections
  - `FilterBar.swift` — grouping mode / tag filter controls

---

## P2 — Testability & Architecture

- [ ] **7. Extract MarkdownParser from TodoList**
  `TodoList.swift:587-730` — `loadTodos()` is private and untestable. Extract into a `MarkdownParser` struct with a pure function:
  ```swift
  struct MarkdownParser {
      static func parse(_ content: String) -> ParsedTodoFile
  }
  ```
  This enables testing every parsing edge case (malformed files, empty sections, missing headers).

- [ ] **8. Extract MarkdownWriter from TodoList**
  `TodoList.swift:454-575` — `performSave()` builds markdown. Extract into:
  ```swift
  struct MarkdownWriter {
      static func write(_ data: ParsedTodoFile) -> String
  }
  ```
  Enables round-trip tests: parse → write → parse → assert equal.

- [ ] **9. Fix `@State var todo` ownership in TodoItemView**
  `TodoItemView.swift:89` — Using `@State` for a todo that's also managed by `TodoList` creates dual sources of truth. The manual refresh pattern (item 4) is a symptom. Consider using a `Binding<Todo>` or computing the view directly from TodoList state.

---

## P3 — Error Handling

- [ ] **10. Handle `try?` in file creation**
  `TodoList.swift:127` — `try? content.write(...)` silently fails when creating new files. User thinks file was created but it wasn't.

- [ ] **11. Better API error feedback**
  `ClaudeCategorizationService.swift` — Network errors, rate limits, and invalid API keys all surface as generic "Failed to categorize" messages. Show specific error info.

---

## P4 — Thread Safety

- [ ] **12. Synchronize mutable statics in Theme.swift**
  `Theme.swift:88-89` — `usedColors` and `tagColorMap` are mutable static `Set`/`Dictionary` with no synchronization. Concurrent SwiftUI view updates could corrupt them. Use a lock or actor.

---

## P5 — Performance

- [ ] **13. Cache `processedTodos` computation**
  `TodoListView.swift` — `processedTodos` is a computed property recalculated on every access. With many todos, this is O(n) per frame. Cache it and invalidate on data change.

- [ ] **14. AnyView type erasure in TagRowView**
  `TodoItemView.swift:713` — `TagRowView` is a function returning `AnyView`, which disables SwiftUI diffing optimizations. Convert to a proper `struct View`.

---

## P6 — Accessibility

- [ ] **15. Add accessibility labels to checkboxes**
  `TodoItemView.swift:185-198` and `TodoListView.swift` Top5ItemRow — Checkboxes have no `.accessibilityLabel()`. VoiceOver users can't distinguish them.

- [ ] **16. Don't rely on color alone for priority/tags**
  Priority indicators and tag pills use color as the sole differentiator. Add icons or text labels for colorblind users (WCAG 1.4.1).

---

## P7 — Polish

- [ ] **17. Add loading spinner for AI operations**
  Currently shows "Analyzing..." text only. Add a `ProgressView()` spinner.

- [ ] **18. Make backup interval configurable**
  `TodoList.swift:26` — Hardcoded to 3 hours. Add to Settings.

- [ ] **19. Consolidate redundant `updateTodo` methods**
  `TodoList.swift:295,302` — Two `updateTodo` overloads that do similar things. Merge into one.
