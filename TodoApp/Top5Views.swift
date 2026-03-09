import SwiftUI

// Suggestion chip for AI-suggested tags
struct SuggestionChip: View {
    let tag: String
    let isSelected: Bool
    let isContext: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if isContext {
                    Image(systemName: iconForContext(tag))
                        .font(.system(size: 8))
                }
                Text("#\(tag)")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : Theme.colorForTag(tag))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.colorForTag(tag) : Theme.colorForTag(tag).opacity(0.2))
            )
            .overlay(
                Capsule()
                    .stroke(isContext ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconForContext(_ context: String) -> String {
        switch context.lowercased() {
        case "prep": return "calendar"
        case "reply": return "arrowshape.turn.up.left"
        case "deep": return "brain.head.profile"
        case "waiting": return "hourglass"
        default: return "tag"
        }
    }
}


// Prominent sticky Top 5 section
struct Top5WeekSection: View {
    @ObservedObject var todoList: TodoList
    @State private var isAddingNew = false
    @State private var newItemTitle = ""
    @FocusState private var addFieldFocused: Bool

    private let sectionColor = Color.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(sectionColor)
                    .frame(width: 16, height: 16)

                Text("Top 5 of the Week")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)

                Text("\(todoList.top5Todos.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(sectionColor))

                Spacer()

                if !todoList.top5Todos.isEmpty {
                    Button(action: { todoList.clearTop5() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Clear Top 5 and start fresh")
                }

                if todoList.top5Todos.count < 5 {
                    Button(action: {
                        isAddingNew = true
                        addFieldFocused = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(sectionColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Add item to Top 5")
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.vertical, 12)
            .background(sectionColor.opacity(0.05))

            // Colored line under header
            Rectangle()
                .fill(sectionColor.opacity(0.5))
                .frame(height: 2)

            // Items list
            VStack(spacing: 0) {
                ForEach(Array(todoList.top5Todos.enumerated()), id: \.element.id) { index, todo in
                    Top5ItemRow(todoList: todoList, todo: todo, rank: index + 1)
                }

                // Inline add field or empty state
                if isAddingNew {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(sectionColor.opacity(0.5))

                        TextField("New Top 5 item...", text: $newItemTitle)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(Theme.bodyFont)
                            .focused($addFieldFocused)
                            .onSubmit {
                                addNewItem()
                            }

                        Button("Cancel") {
                            isAddingNew = false
                            newItemTitle = ""
                        }
                        .font(.caption)
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                } else if todoList.top5Todos.isEmpty {
                    Button(action: {
                        isAddingNew = true
                        addFieldFocused = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.dashed")
                                .font(.system(size: 13))
                            Text("What are your top priorities this week?")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadiusMd)
        .overlay(
            Rectangle()
                .fill(sectionColor)
                .frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .stroke(sectionColor.opacity(0.15), lineWidth: 1)
        )
        .padding(.top, 6)
        .padding(.bottom, 16)
        .padding(.horizontal, Theme.contentPadding)
    }

    private func addNewItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let todo = Todo(title: title, priority: .thisWeek)
        todoList.addTop5Todo(todo)
        newItemTitle = ""
        isAddingNew = false
    }
}

// Compact row for Top 5 items with inline editing
struct Top5ItemRow: View {
    @ObservedObject var todoList: TodoList
    @State var todo: Todo
    let rank: Int
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @FocusState private var editFocused: Bool

    // AI suggestion state
    @State private var isLoadingAI = false
    @State private var showingAISuggestion = false
    @State private var suggestedContext: String? = nil

    private let accentColor = Color.blue

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: {
                todoList.toggleTop5Todo(todo)
                refreshTodo()
            }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(todo.isCompleted ? .green : Theme.secondaryText)
            }
            .buttonStyle(PlainButtonStyle())

            if isEditing {
                TextField("Title", text: $editedTitle)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(Theme.bodyFont)
                    .focused($editFocused)
                    .onSubmit { saveEdit() }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Theme.background)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(accentColor.opacity(0.5), lineWidth: 1)
                    )
            } else {
                // Title
                Text(todo.title)
                    .font(Theme.bodyFont)
                    .foregroundColor(todo.isCompleted ? Theme.secondaryText : Theme.text)
                    .strikethrough(todo.isCompleted)
                    .lineLimit(1)
            }

            Spacer()

            // Tags (compact)
            if !isEditing {
                ForEach(todo.tags.prefix(2), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.colorForTag(tag))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isEditing ? accentColor.opacity(0.08) : (isHovered ? accentColor.opacity(0.06) : Color.clear))
        )
        .animation(Theme.Animation.quickFade, value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .gesture(
            TapGesture(count: 2).onEnded {
                editedTitle = todo.title
                isEditing = true
                editFocused = true
            }
        )
        .onChange(of: editFocused) { _, focused in
            if !focused && isEditing { saveEdit() }
        }
        .contextMenu {
            // Edit
            Button {
                editedTitle = todo.title
                isEditing = true
                editFocused = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            // Move up / down
            Button {
                todoList.moveTop5Todo(todo, direction: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(todoList.top5Todos.first?.id == todo.id)

            Button {
                todoList.moveTop5Todo(todo, direction: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(todoList.top5Todos.last?.id == todo.id)

            Divider()

            // Context tags
            Menu("Context") {
                let contextManager = ContextConfigManager.shared
                ForEach(contextManager.contexts, id: \.id) { context in
                    let hasContext = todo.tags.contains { $0.lowercased() == context.id.lowercased() }
                    Button {
                        if hasContext {
                            todoList.removeTagFromTop5Todo(todo, tag: context.id)
                        } else {
                            todoList.addTagToTop5Todo(todo, tag: context.id)
                        }
                        refreshTodo()
                    } label: {
                        Label {
                            Text(context.name)
                        } icon: {
                            Image(systemName: hasContext ? "checkmark.circle.fill" : context.icon)
                        }
                    }
                }
            }

            // Tags
            Menu("Tags") {
                if !todo.tags.isEmpty {
                    ForEach(todo.tags, id: \.self) { tag in
                        Button {
                            todoList.removeTagFromTop5Todo(todo, tag: tag)
                            refreshTodo()
                        } label: {
                            Label("Remove #\(tag)", systemImage: "minus.circle")
                        }
                    }
                    Divider()
                }
                let availableTags = todoList.allTags.filter { !todo.tags.contains($0) }
                ForEach(availableTags, id: \.self) { tag in
                    Button {
                        todoList.addTagToTop5Todo(todo, tag: tag)
                        refreshTodo()
                    } label: {
                        Label("Add #\(tag)", systemImage: "plus.circle")
                    }
                }
            }

            // AI Auto-tag
            if APIKeyManager.shared.hasAPIKey {
                Button {
                    fetchAISuggestion()
                } label: {
                    Label(isLoadingAI ? "Analyzing..." : "Auto-tag with AI", systemImage: "sparkles")
                }
                .disabled(isLoadingAI)
            }

            Divider()

            // Complete / Uncomplete
            Button {
                todoList.toggleTop5Todo(todo)
                refreshTodo()
            } label: {
                Label(todo.isCompleted ? "Mark Incomplete" : "Mark Complete", systemImage: todo.isCompleted ? "circle" : "checkmark.circle")
            }

            // Remove from Top 5
            Button(role: .destructive) {
                todoList.deleteTop5Todo(todo)
            } label: {
                Label("Remove from Top 5", systemImage: "star.slash")
            }
        }
        .alert("AI Suggestion", isPresented: $showingAISuggestion) {
            if let context = suggestedContext {
                Button("Add #\(context)") {
                    todoList.addTagToTop5Todo(todo, tag: context)
                    refreshTodo()
                    suggestedContext = nil
                }
            }
            Button("Cancel", role: .cancel) { suggestedContext = nil }
        } message: {
            if let context = suggestedContext {
                Text("Add context tag #\(context) to this todo?")
            } else {
                Text("No context suggestion available for this todo.")
            }
        }
    }

    /// Re-sync local @State todo from TodoList after a mutation
    private func refreshTodo() {
        if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
            todo = updated
        }
    }

    private func saveEdit() {
        let title = editedTitle.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            var updated = todo
            updated.title = title
            todoList.updateTop5Todo(updated)
            todo = updated
        }
        isEditing = false
    }

    private func fetchAISuggestion() {
        guard !isLoadingAI else { return }
        isLoadingAI = true
        Task {
            do {
                let suggestion = try await ClaudeCategorizationService.shared.suggestTags(
                    todoText: todo.title,
                    existingTags: todoList.allTags
                )
                await MainActor.run {
                    isLoadingAI = false
                    suggestedContext = suggestion.context
                    showingAISuggestion = true
                }
            } catch {
                await MainActor.run {
                    isLoadingAI = false
                    suggestedContext = nil
                    showingAISuggestion = true
                }
            }
        }
    }
}
