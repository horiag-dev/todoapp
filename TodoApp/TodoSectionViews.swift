import SwiftUI
import AppKit

// Section configuration for priority-based display
struct PrioritySection: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color

    static let today = PrioritySection(id: "today", title: "Today", icon: "pin.fill", color: Theme.todayTagColor)
    static let urgent = PrioritySection(id: "urgent", title: "Urgent", icon: "flame.fill", color: Theme.urgentTagColor)
    static let thisWeek = PrioritySection(id: "thisweek", title: "This Week", icon: "calendar.badge.exclamationmark", color: Theme.thisWeekTagColor)
    static let normal = PrioritySection(id: "normal", title: "Normal", icon: "tray.full", color: .gray)
    static let completed = PrioritySection(id: "completed", title: "Completed", icon: "checkmark.circle.fill", color: .green)
}

struct TodoListSections: View {
    @ObservedObject var todoList: TodoList
    var excludeTop5: Bool = false
    var searchText: String = ""

    // MARK: - Performance Optimized Data Structures

    private struct TodoMeta {
        let todo: Todo
        let titleLower: String
        let tagsLower: Set<String>
        let hasToday: Bool
        let hasUrgent: Bool
        let hasThisWeek: Bool
    }

    private struct CategorizedTodos {
        var today: [TodoMeta] = []
        var urgent: [TodoMeta] = []
        var thisWeek: [TodoMeta] = []
        var normal: [TodoMeta] = []
        var completed: [TodoMeta] = []
    }

    private var searchFilter: String {
        searchText.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private var processedTodos: [TodoMeta] {
        let filter = searchFilter

        return todoList.todos.compactMap { todo in
            let titleLower = todo.title.lowercased()
            let tagsLower = Set(todo.tags.map { $0.lowercased() })

            if !filter.isEmpty {
                let matchesTitle = titleLower.contains(filter)
                let matchesTags = tagsLower.contains { $0.contains(filter) }
                if !matchesTitle && !matchesTags { return nil }
            }

            return TodoMeta(
                todo: todo,
                titleLower: titleLower,
                tagsLower: tagsLower,
                hasToday: todo.priority == .today,
                hasUrgent: tagsLower.contains("urgent") || todo.priority == .urgent,
                hasThisWeek: tagsLower.contains("thisweek") || todo.priority == .thisWeek
            )
        }
    }

    private var categorizedTodos: CategorizedTodos {
        var result = CategorizedTodos()

        for meta in processedTodos {
            if meta.todo.isCompleted {
                result.completed.append(meta)
                continue
            }

            // Priority order: today > urgent > thisWeek > normal
            if meta.hasToday {
                result.today.append(meta)
            } else if meta.hasUrgent {
                result.urgent.append(meta)
            } else if meta.hasThisWeek {
                result.thisWeek.append(meta)
            } else {
                result.normal.append(meta)
            }
        }

        return result
    }

    private func sortByTitle(_ metas: [TodoMeta]) -> [Todo] {
        metas.sorted { $0.titleLower < $1.titleLower }.map { $0.todo }
    }

    private func matchesSearch(_ todo: Todo) -> Bool {
        guard !searchFilter.isEmpty else { return true }
        if todo.title.lowercased().contains(searchFilter) { return true }
        if todo.tags.contains(where: { $0.lowercased().contains(searchFilter) }) { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top 5 of the week section
            if !excludeTop5 && !todoList.top5Todos.isEmpty {
                TodoPrioritySection(
                    todoList: todoList,
                    section: PrioritySection(id: "top5", title: "Top 5 of the Week", icon: "star.fill", color: .blue),
                    todos: todoList.top5Todos,
                    isTop5: true
                )
            }

            // Priority sections
            let cats = categorizedTodos

            let todayTodos = sortByTitle(cats.today)
            if !todayTodos.isEmpty {
                TodoPrioritySection(todoList: todoList, section: .today, todos: todayTodos)
            }

            let urgentTodos = sortByTitle(cats.urgent)
            if !urgentTodos.isEmpty {
                TodoPrioritySection(todoList: todoList, section: .urgent, todos: urgentTodos)
            }

            let thisWeekTodos = sortByTitle(cats.thisWeek)
            if !thisWeekTodos.isEmpty {
                TodoPrioritySection(todoList: todoList, section: .thisWeek, todos: thisWeekTodos)
            }

            let normalTodos = sortByTitle(cats.normal)
            if !normalTodos.isEmpty {
                TodoPrioritySection(todoList: todoList, section: .normal, todos: normalTodos)
            }

            // Reading List section
            if !todoList.readingList.isEmpty {
                ReadingListSection(todoList: todoList)
            }

            let completedTodos = sortByTitle(cats.completed)
            if !completedTodos.isEmpty {
                TodoPrioritySection(todoList: todoList, section: .completed, todos: completedTodos)
            }

            // Deleted section
            if !todoList.deletedTodos.isEmpty {
                DisclosureGroup(
                    isExpanded: $todoList.isDeletedSectionCollapsed,
                    content: {
                        ForEach(todoList.deletedTodos) { todo in
                            HStack {
                                Text(todo.title)
                                    .strikethrough()
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, Theme.contentPadding)
                        }
                    },
                    label: {
                        HStack {
                            Text("Deleted Items")
                            Text("(\(todoList.deletedTodos.count))")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, Theme.contentPadding)
                    }
                )
                .padding(.vertical, Theme.itemSpacing)
                .background(Theme.cardBackground)
            }
        }
        .padding(.bottom)
    }
}

// Priority-based section view
struct TodoPrioritySection: View {
    @ObservedObject var todoList: TodoList
    let section: PrioritySection
    let todos: [Todo]
    var isTop5: Bool = false

    var body: some View {
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Section header
                HStack(spacing: 10) {
                    Image(systemName: section.icon)
                        .font(.system(size: 14))
                        .foregroundColor(section.color)
                        .frame(width: 16, height: 16)

                    Text(section.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(section.id == "today" || section.id == "urgent" ? section.color : Theme.text)

                    Text("\(todos.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(section.color)
                        )

                    Spacer()

                    if section.id == "completed" {
                        Button(action: { todoList.moveAllCompletedToDeleted() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                Text("Clear")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if section.id == "today" {
                        Button(action: { todoList.clearTodayTags() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 11))
                                Text("Clear")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(section.color.opacity(0.8))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Remove today priority from all items")
                    }
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.vertical, 12)
                .background(
                    section.color.opacity(section.id == "today" || section.id == "urgent" ? 0.1 : 0.06)
                )

                Rectangle()
                    .fill(section.color.opacity(0.5))
                    .frame(height: 2)

                LazyVStack(spacing: 0) {
                    ForEach(todos) { todo in
                        TodoItemView(todoList: todoList, todo: todo, isTop5: isTop5, groupColor: section.color)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(
                ZStack {
                    Theme.cardBackground
                    section.color.opacity(0.04)
                }
            )
            .cornerRadius(Theme.cornerRadiusMd)
            .overlay(
                Rectangle()
                    .fill(section.color)
                    .frame(width: 3),
                alignment: .leading
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                    .stroke(section.color.opacity(0.15), lineWidth: 1)
            )
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
}

// Reading List section styled like priority sections
struct ReadingListSection: View {
    @ObservedObject var todoList: TodoList
    @State private var isAdding = false
    @State private var newItem = ""
    @FocusState private var addFocused: Bool

    private let sectionColor = Color.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 10) {
                Image(systemName: "book.fill")
                    .font(.system(size: 14))
                    .foregroundColor(sectionColor)
                    .frame(width: 16, height: 16)

                Text("To Read")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)

                Text("\(todoList.readingList.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(sectionColor))

                Spacer()

                Button(action: {
                    isAdding = true
                    addFocused = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(sectionColor)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Add link or article")
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.vertical, 12)
            .background(sectionColor.opacity(0.06))

            Rectangle()
                .fill(sectionColor.opacity(0.5))
                .frame(height: 2)

            // Items
            LazyVStack(spacing: 0) {
                ForEach(Array(todoList.readingList.enumerated()), id: \.offset) { index, item in
                    ReadingListItem(item: item) {
                        todoList.removeReadingItem(at: index)
                    }
                }

                if isAdding {
                    HStack(spacing: 6) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 11))
                            .foregroundColor(sectionColor.opacity(0.5))

                        TextField("Paste link or title...", text: $newItem)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 12))
                            .focused($addFocused)
                            .onSubmit { addItem() }

                        Button("Cancel") {
                            isAdding = false
                            newItem = ""
                        }
                        .font(.system(size: 10))
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, Theme.contentPadding)
                    .padding(.vertical, 6)
                }
            }
            .padding(.vertical, 4)
        }
        .background(
            ZStack {
                Theme.cardBackground
                sectionColor.opacity(0.04)
            }
        )
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
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func addItem() {
        let item = newItem.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return }
        todoList.addReadingItem(item)
        newItem = ""
        isAdding = false
    }
}

struct TagListView: View {
    @ObservedObject var todoList: TodoList
    @Binding var selectedTag: String?
    @State private var showingExportAlert = false
    @State private var exportMessage = ""
    @State private var editingTag: String? = nil
    @State private var editedTagName: String = ""

    private var todosByTag: [String: [Todo]] {
        var result: [String: [Todo]] = [:]
        for todo in todoList.todos {
            for tag in todo.tags {
                result[tag, default: []].append(todo)
            }
        }
        return result
    }

    var body: some View {
        List {
            ForEach(todoList.allTags, id: \.self) { tag in
                Section(header:
                    HStack {
                        if editingTag == tag {
                            TextField("Tag name", text: $editedTagName, onCommit: {
                                updateTagName(from: tag, to: editedTagName)
                            })
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onExitCommand {
                                editingTag = nil
                            }
                        } else {
                            TagPillView(tag: tag, size: .small)
                                .onTapGesture(count: 2) {
                                    editingTag = tag
                                    editedTagName = tag
                                }
                        }

                        Spacer()

                        Button(action: { exportTodos(for: tag) }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Export to Notes")
                    }
                ) {
                    ForEach(todosByTag[tag] ?? []) { todo in
                        SimpleTodoItemView(todo: todo, todoList: todoList)
                    }
                }
            }
        }
        .listStyle(.inset)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadius)
        .padding(.horizontal, Theme.contentPadding)
        .alert("Export to Notes", isPresented: $showingExportAlert) {
            Button("Copy to Clipboard") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(exportMessage, forType: .string)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The todos have been formatted for Notes. Would you like to copy them to the clipboard?")
        }
    }

    private func updateTagName(from oldTag: String, to newTag: String) {
        if !newTag.isEmpty && newTag != oldTag {
            for todo in todoList.todos {
                if todo.tags.contains(oldTag) {
                    var updatedTags = todo.tags
                    if let index = updatedTags.firstIndex(of: oldTag) {
                        updatedTags[index] = newTag
                        todoList.updateTodo(todo, withTags: updatedTags)
                    }
                }
            }
            todoList.renameTag(from: oldTag, to: newTag)
        }
        editingTag = nil
    }

    private func exportTodos(for tag: String) {
        let todos = todoList.todos.filter { $0.tags.contains(tag) }
        var formattedText = "# \(tag)\n\n"
        for todo in todos {
            let checkbox = todo.isCompleted ? "- [x]" : "- [ ]"
            formattedText += "\(checkbox) \(todo.title)\n"
        }
        exportMessage = formattedText
        showingExportAlert = true
    }
}

struct SimpleTodoItemView: View {
    let todo: Todo
    @ObservedObject var todoList: TodoList

    var body: some View {
        HStack {
            Button(action: { todoList.toggleTodo(todo) }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? .green : .gray)
            }
            .buttonStyle(PlainButtonStyle())

            Text(todo.title)
                .strikethrough(todo.isCompleted)
                .foregroundColor(todo.isCompleted ? .gray : .primary)

            Spacer()

            Image(systemName: todo.priority.icon)
                .foregroundColor(todo.priority.color)
        }
        .padding(.vertical, 4)
    }
}

// Resizable bar between columns
struct ResizableBar: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 12)
                .contentShape(Rectangle())

            RoundedRectangle(cornerRadius: 1)
                .fill(isDragging ? Theme.accent : (isHovered ? Theme.accent.opacity(0.5) : Theme.divider.opacity(0.5)))
                .frame(width: isDragging ? 3 : (isHovered ? 2 : 1))
                .animation(Theme.Animation.quickFade, value: isHovered)
                .animation(Theme.Animation.quickFade, value: isDragging)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else if !isDragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    let newWidth = width + value.translation.width
                    width = min(max(minWidth, newWidth), maxWidth)
                }
                .onEnded { _ in
                    isDragging = false
                    if !isHovered {
                        NSCursor.pop()
                    }
                }
        )
    }
}
