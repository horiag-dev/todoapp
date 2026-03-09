import SwiftUI
import AppKit

// Grouping mode for todo list
enum GroupingMode: String, CaseIterable {
    case contextMode = "Context"   // Group by context tags (prep, reply, deep, waiting)
    case tagMode = "Tags"          // Group by any tags, sorted by frequency
}

// Context section configuration
struct ContextSection: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let contextTag: String? // nil for special sections like Today, Urgent, Other

    static let today = ContextSection(id: "today", title: "Today", icon: "pin.fill", color: Theme.todayTagColor, contextTag: nil)
    static let thisWeek = ContextSection(id: "thisweek", title: "This Week", icon: "calendar.badge.exclamationmark", color: Theme.thisWeekTagColor, contextTag: nil)
    static let urgent = ContextSection(id: "urgent", title: "Urgent", icon: "flame.fill", color: Theme.urgentTagColor, contextTag: nil)
    static let other = ContextSection(id: "other", title: "Other", icon: "tray", color: .gray, contextTag: nil)
    static let completed = ContextSection(id: "completed", title: "Completed", icon: "checkmark.circle.fill", color: .green, contextTag: nil)

    // Get context tags from configuration
    static var contextTags: [String] {
        ContextConfigManager.shared.contextTags
    }

    // Build context sections from configuration
    static var contextSections: [ContextSection] {
        var sections = ContextConfigManager.shared.contexts.map { config in
            ContextSection(
                id: config.id,
                title: config.name,
                icon: config.icon,
                color: config.color,
                contextTag: config.id
            )
        }
        sections.append(.other)
        return sections
    }

    // Get a section for a specific context tag
    static func section(for contextTag: String) -> ContextSection? {
        if let config = ContextConfigManager.shared.context(for: contextTag) {
            return ContextSection(
                id: config.id,
                title: config.name,
                icon: config.icon,
                color: config.color,
                contextTag: config.id
            )
        }
        return nil
    }
}

struct TodoListSections: View {
    @ObservedObject var todoList: TodoList
    var excludeTop5: Bool = false
    @Binding var groupingMode: GroupingMode
    var searchText: String = ""

    // MARK: - Performance Optimized Data Structures

    /// Pre-computed todo metadata for O(1) lookups during filtering
    private struct TodoMeta {
        let todo: Todo
        let titleLower: String
        let tagsLower: Set<String>
        let hasToday: Bool
        let hasThisWeek: Bool
        let hasUrgent: Bool
        let hasContextTag: Bool
        let primaryContextTag: String?
    }

    /// Single-pass categorization result
    private struct CategorizedTodos {
        var today: [TodoMeta] = []
        var thisWeek: [TodoMeta] = []
        var urgent: [TodoMeta] = []
        var normal: [TodoMeta] = []
        var completed: [TodoMeta] = []
    }

    // Pre-compute search filter once
    private var searchFilter: String {
        searchText.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Pre-process all todos once with lowercase values and tag flags
    private var processedTodos: [TodoMeta] {
        let contextManager = ContextConfigManager.shared
        let filter = searchFilter

        return todoList.todos.compactMap { todo in
            let titleLower = todo.title.lowercased()
            let tagsLower = Set(todo.tags.map { $0.lowercased() })

            // Search filter check (early exit)
            if !filter.isEmpty {
                let matchesTitle = titleLower.contains(filter)
                let matchesTags = tagsLower.contains { $0.contains(filter) }
                if !matchesTitle && !matchesTags { return nil }
            }

            // Pre-compute flags (priority-based for today, tag-based for others)
            let hasToday = todo.priority == .today
            let hasThisWeek = tagsLower.contains("thisweek")
            let hasUrgent = tagsLower.contains("urgent")

            // Find primary context tag
            var primaryContextTag: String? = nil
            var hasContextTag = false
            for tag in tagsLower {
                if contextManager.isContextTag(tag) {
                    hasContextTag = true
                    if primaryContextTag == nil {
                        primaryContextTag = tag
                    }
                }
            }

            return TodoMeta(
                todo: todo,
                titleLower: titleLower,
                tagsLower: tagsLower,
                hasToday: hasToday,
                hasThisWeek: hasThisWeek,
                hasUrgent: hasUrgent,
                hasContextTag: hasContextTag,
                primaryContextTag: primaryContextTag
            )
        }
    }

    /// Single-pass categorization of all todos
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
            } else if meta.hasUrgent || meta.todo.priority == .urgent {
                result.urgent.append(meta)
            } else if meta.hasThisWeek || meta.todo.priority == .thisWeek {
                result.thisWeek.append(meta)
            } else {
                result.normal.append(meta)
            }
        }

        return result
    }

    /// Sort todos by pre-computed lowercase title
    private func sortByTitle(_ metas: [TodoMeta]) -> [Todo] {
        metas.sorted { $0.titleLower < $1.titleLower }.map { $0.todo }
    }

    // MARK: - Optimized Accessors

    private func todosForUrgency(_ urgencyType: String) -> [Todo] {
        let cats = categorizedTodos
        switch urgencyType {
        case "today": return sortByTitle(cats.today)
        case "thisweek": return sortByTitle(cats.thisWeek)
        case "urgent": return sortByTitle(cats.urgent)
        default: return []
        }
    }

    private func todosByContext(from todos: [Todo], groupOtherByTags: Bool = false) -> [(context: ContextSection, todos: [Todo])] {
        // Build a map of todo IDs to their metadata for O(1) lookup
        let metaMap = Dictionary(uniqueKeysWithValues: processedTodos.map { ($0.todo.id, $0) })
        var result: [(context: ContextSection, todos: [Todo])] = []

        for contextSection in ContextSection.contextSections {
            let contextTodos: [Todo]
            if contextSection.id == "other" {
                contextTodos = todos.filter { todo in
                    guard let meta = metaMap[todo.id] else { return false }
                    return !meta.hasContextTag
                }
            } else if let contextTag = contextSection.contextTag {
                let ctLower = contextTag.lowercased()
                contextTodos = todos.filter { todo in
                    guard let meta = metaMap[todo.id] else { return false }
                    return meta.tagsLower.contains(ctLower)
                }
            } else {
                contextTodos = []
            }

            if !contextTodos.isEmpty {
                // Use pre-computed lowercase for sorting
                let sorted = contextTodos.sorted { t1, t2 in
                    let m1 = metaMap[t1.id]?.titleLower ?? ""
                    let m2 = metaMap[t2.id]?.titleLower ?? ""
                    return m1 < m2
                }
                result.append((contextSection, sorted))
            }
        }

        return result
    }

    private func todosForSection(_ section: ContextSection) -> [Todo] {
        let cats = categorizedTodos

        func sortMetas(_ metas: [TodoMeta]) -> [Todo] {
            metas.sorted { $0.titleLower < $1.titleLower }.map { $0.todo }
        }

        switch section.id {
        case "today":
            return sortMetas(cats.today)

        case "thisweek":
            return sortMetas(cats.thisWeek)

        case "urgent":
            return sortMetas(cats.urgent)

        case "prep", "reply", "deep", "waiting":
            guard let contextTag = section.contextTag else { return [] }
            let ctLower = contextTag.lowercased()
            let filtered = cats.normal.filter { $0.tagsLower.contains(ctLower) }
            return sortMetas(filtered)

        case "other":
            let filtered = cats.normal.filter { !$0.hasContextTag }
            return sortMetas(filtered)

        case "completed":
            return sortMetas(cats.completed)

        default:
            return []
        }
    }

    // Legacy search function (kept for compatibility)
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
                ContextTodoSection(
                    todoList: todoList,
                    section: ContextSection(id: "top5", title: "Top 5 of the Week", icon: "star.fill", color: .blue, contextTag: nil),
                    todos: todoList.top5Todos,
                    isTop5: true
                )
            }

            if groupingMode == .contextMode {
                // CONTEXT MODE: Today/Urgent with context sub-groups
                contextModeView
            } else {
                // TAG MODE: Group by any tags, sorted by frequency
                tagModeView
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

    // Context mode view - Today (flat), Urgent, This Week, Normal with context sub-groups
    @ViewBuilder
    private var contextModeView: some View {
        // Use pre-categorized todos (single-pass optimization)
        let cats = categorizedTodos

        // Today section - simple flat list, no context grouping
        let todayTodos = sortByTitle(cats.today)
        if !todayTodos.isEmpty {
            ContextTodoSection(
                todoList: todoList,
                section: .today,
                todos: todayTodos,
                isTop5: false
            )
        }

        // Urgent section with context sub-groups
        let urgentTodos = sortByTitle(cats.urgent)
        if !urgentTodos.isEmpty {
            UrgencySectionWithContextGroups(
                todoList: todoList,
                urgencySection: .urgent,
                todosByContext: todosByContextOnly(from: urgentTodos)
            )
        }

        // This Week section with context sub-groups
        let thisWeekTodos = sortByTitle(cats.thisWeek)
        if !thisWeekTodos.isEmpty {
            UrgencySectionWithContextGroups(
                todoList: todoList,
                urgencySection: .thisWeek,
                todosByContext: todosByContextOnly(from: thisWeekTodos)
            )
        }

        // Normal priority todos - with context sub-groups
        let normalTodos = sortByTitle(cats.normal)
        if !normalTodos.isEmpty {
            UrgencySectionWithContextGroups(
                todoList: todoList,
                urgencySection: ContextSection(id: "normal", title: "Normal", icon: "tray.full", color: .gray, contextTag: nil),
                todosByContext: todosByContextOnly(from: normalTodos)
            )
        }

        // Completed section
        let completedTodos = sortByTitle(cats.completed)
        if !completedTodos.isEmpty {
            ContextTodoSection(
                todoList: todoList,
                section: .completed,
                todos: completedTodos,
                isTop5: false
            )
        }
    }

    // Get todos grouped by context only - "Other" is a flat list (no tag headers)
    private func todosByContextOnly(from todos: [Todo]) -> [(context: ContextSection, todos: [Todo])] {
        var result: [(context: ContextSection, todos: [Todo])] = []

        // Build metadata map from pre-computed data for O(1) lookups
        let metaMap = Dictionary(uniqueKeysWithValues: processedTodos.map { ($0.todo.id, $0) })

        // Group by context tags using pre-computed lowercase tags
        for contextSection in ContextSection.contextSections {
            if contextSection.id == "other" {
                continue // Handle "Other" separately
            }
            if let contextTag = contextSection.contextTag {
                let ctLower = contextTag.lowercased()
                let contextTodos = todos.filter { todo in
                    metaMap[todo.id]?.tagsLower.contains(ctLower) ?? false
                }
                if !contextTodos.isEmpty {
                    // Sort using pre-computed lowercase titles
                    let sorted = contextTodos.sorted {
                        (metaMap[$0.id]?.titleLower ?? "") < (metaMap[$1.id]?.titleLower ?? "")
                    }
                    result.append((contextSection, sorted))
                }
            }
        }

        // "Other" - todos without context tags (using pre-computed flag)
        let otherTodos = todos.filter { todo in
            !(metaMap[todo.id]?.hasContextTag ?? true)
        }

        if !otherTodos.isEmpty {
            // Count tag frequency in single pass
            var tagCounts: [String: Int] = [:]
            var tagLowerMap: [String: String] = [:]  // Cache lowercase versions
            for todo in otherTodos {
                for tag in todo.tags {
                    tagCounts[tag, default: 0] += 1
                    if tagLowerMap[tag] == nil {
                        tagLowerMap[tag] = tag.lowercased()
                    }
                }
            }

            // Sort tags by frequency (descending), then alphabetically
            let sortedTags = tagCounts.keys.sorted { tag1, tag2 in
                let count1 = tagCounts[tag1] ?? 0
                let count2 = tagCounts[tag2] ?? 0
                if count1 != count2 { return count1 > count2 }
                return tagLowerMap[tag1, default: ""] < tagLowerMap[tag2, default: ""]
            }

            // Build tag index map for O(1) lookup instead of O(n) firstIndex
            let tagIndex = Dictionary(uniqueKeysWithValues: sortedTags.enumerated().map { ($1, $0) })

            // Assign each todo to its highest-priority (most frequent) tag
            var primaryTag: [UUID: String] = [:]
            var primaryTagIndex: [UUID: Int] = [:]  // Cache the index too
            for todo in otherTodos {
                for tag in sortedTags {
                    if todo.tags.contains(tag) {
                        primaryTag[todo.id] = tag
                        primaryTagIndex[todo.id] = tagIndex[tag] ?? Int.max
                        break
                    }
                }
            }

            // Sort todos: group by primary tag (in frequency order), then by title within group
            let sortedOther = otherTodos.sorted { todo1, todo2 in
                let idx1 = primaryTagIndex[todo1.id] ?? Int.max
                let idx2 = primaryTagIndex[todo2.id] ?? Int.max

                // Compare by tag priority
                if idx1 != idx2 { return idx1 < idx2 }

                // Same tag or both untagged - sort by title (using pre-computed lowercase)
                let title1 = metaMap[todo1.id]?.titleLower ?? ""
                let title2 = metaMap[todo2.id]?.titleLower ?? ""
                return title1 < title2
            }

            result.append((.other, sortedOther))
        }

        return result
    }

    // Compute tag groups for tag mode - each todo assigned to exactly one group
    // Excludes context tags (prep, reply, deep, waiting) - only shows actual tags
    private func computeTagGroups() -> [(tag: String?, todos: [Todo])] {
        let incompleteTodos = todoList.todos.filter { !$0.isCompleted && matchesSearch($0) }
        let contextManager = ContextConfigManager.shared

        // Single pass: count tags and cache non-context tags per todo
        var tagCounts: [String: Int] = [:]
        var tagLowerMap: [String: String] = [:]
        var todoNonContextTags: [UUID: [String]] = [:]

        for todo in incompleteTodos {
            var nonContextTags: [String] = []
            for tag in todo.tags {
                // O(1) context check
                if contextManager.isContextTag(tag) {
                    continue
                }
                nonContextTags.append(tag)
                tagCounts[tag, default: 0] += 1
                if tagLowerMap[tag] == nil {
                    tagLowerMap[tag] = tag.lowercased()
                }
            }
            todoNonContextTags[todo.id] = nonContextTags
        }

        // Sort tags by count (descending), then alphabetically
        let sortedTags = tagCounts.keys.sorted { tag1, tag2 in
            let count1 = tagCounts[tag1] ?? 0
            let count2 = tagCounts[tag2] ?? 0
            if count1 != count2 {
                return count1 > count2
            }
            return tagLowerMap[tag1, default: ""] < tagLowerMap[tag2, default: ""]
        }

        // Build tag index for O(1) lookup
        let tagIndex = Dictionary(uniqueKeysWithValues: sortedTags.enumerated().map { ($1, $0) })

        // Assign each todo to its highest-priority tag and group directly
        var todosByTag: [String: [Todo]] = [:]
        var untaggedTodos: [Todo] = []

        for todo in incompleteTodos {
            let nonContextTags = todoNonContextTags[todo.id] ?? []
            if nonContextTags.isEmpty {
                untaggedTodos.append(todo)
                continue
            }
            // Find the highest priority tag (lowest index in sortedTags)
            var bestTag: String? = nil
            var bestIndex = Int.max
            for tag in nonContextTags {
                if let idx = tagIndex[tag], idx < bestIndex {
                    bestIndex = idx
                    bestTag = tag
                }
            }
            if let tag = bestTag {
                todosByTag[tag, default: []].append(todo)
            }
        }

        // Build groups in sorted order
        var groups: [(tag: String?, todos: [Todo])] = []
        for tag in sortedTags {
            if let todos = todosByTag[tag], !todos.isEmpty {
                groups.append((tag: tag, todos: todos))
            }
        }

        if !untaggedTodos.isEmpty {
            groups.append((tag: nil, todos: untaggedTodos))
        }

        return groups
    }

    // Tag mode view - group by any tag, sorted by frequency
    @ViewBuilder
    private var tagModeView: some View {
        let tagGroups = computeTagGroups()

        ForEach(Array(tagGroups.enumerated()), id: \.offset) { _, group in
            TagGroupSection(
                todoList: todoList,
                tag: group.tag,
                todos: group.todos,
                count: group.todos.count
            )
        }

        // Completed section
        let completedTodos = todoList.todos.filter { $0.isCompleted && matchesSearch($0) }
        if !completedTodos.isEmpty {
            ContextTodoSection(
                todoList: todoList,
                section: .completed,
                todos: completedTodos,
                isTop5: false
            )
        }
    }
}

// Urgency section (Today/Urgent) with context sub-groups inside
struct UrgencySectionWithContextGroups: View {
    @ObservedObject var todoList: TodoList
    let urgencySection: ContextSection
    let todosByContext: [(context: ContextSection, todos: [Todo])]

    var totalCount: Int {
        todosByContext.reduce(0) { $0 + $1.todos.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main urgency header
            HStack(spacing: 10) {
                Image(systemName: urgencySection.icon)
                    .font(.system(size: 14))
                    .foregroundColor(urgencySection.color)

                Text(urgencySection.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(urgencySection.color)

                Text("\(totalCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(urgencySection.color))

                Spacer()

                // Clear Today button (only for Today section)
                if urgencySection.id == "today" {
                    Button(action: { todoList.clearTodayTags() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11))
                            Text("Clear")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(urgencySection.color.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Remove #today tag from all items")
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.vertical, 12)
            .background(urgencySection.color.opacity(0.08))

            Rectangle()
                .fill(urgencySection.color.opacity(0.5))
                .frame(height: 2)

            // Context sub-groups
            VStack(spacing: 0) {
                ForEach(todosByContext, id: \.context.id) { item in
                    ContextSubGroup(
                        todoList: todoList,
                        context: item.context,
                        todos: item.todos,
                        parentColor: urgencySection.color
                    )
                }
            }
            .padding(.bottom, 4)
        }
        .background(
            ZStack {
                Theme.cardBackground
                urgencySection.color.opacity(0.04)
            }
        )
        .cornerRadius(Theme.cornerRadiusMd)
        .overlay(
            Rectangle()
                .fill(urgencySection.color)
                .frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .stroke(urgencySection.color.opacity(0.15), lineWidth: 1)
        )
        .padding(.vertical, 6)
    }
}

// Context sub-group within an urgency section
struct ContextSubGroup: View {
    @ObservedObject var todoList: TodoList
    let context: ContextSection
    let todos: [Todo]
    let parentColor: Color

    var body: some View {
        // For "other" context, just list todos without a header
        if context.id == "other" {
            LazyVStack(spacing: 0) {
                ForEach(todos) { todo in
                    TodoItemView(todoList: todoList, todo: todo, isTop5: false, groupColor: parentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Sub-group with left color bar for clear identification
                HStack(spacing: 0) {
                    // Left color indicator bar
                    Rectangle()
                        .fill(context.color)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 0) {
                        // Sub-group header
                        HStack(spacing: 6) {
                            Image(systemName: context.icon)
                                .font(.system(size: 11))
                                .foregroundColor(context.color)

                            Text(context.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(context.color)

                            Text("\(todos.count)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(context.color)
                                )

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(context.color.opacity(0.08))

                        // Todos in this context - with context background color (lazy for performance)
                        LazyVStack(spacing: 0) {
                            ForEach(todos) { todo in
                                TodoItemView(todoList: todoList, todo: todo, isTop5: false, groupColor: context.color)
                            }
                        }
                    }
                }
                .background(Theme.cardBackground)
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }
}

// Tag-based section view for tag mode grouping
struct TagGroupSection: View {
    @ObservedObject var todoList: TodoList
    let tag: String?  // nil for untagged
    let todos: [Todo]
    let count: Int

    private var tagColor: Color {
        if let tag = tag {
            return Theme.colorForTag(tag)
        }
        return .gray
    }

    private var displayName: String {
        tag ?? "Untagged"
    }

    private var icon: String {
        if let tag = tag {
            return ContextConfigManager.shared.icon(for: tag)
        }
        return "tray"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Left color bar
                Rectangle()
                    .fill(tagColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(tagColor)

                        Text(displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.text)

                        Text("\(todos.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(tagColor)
                            )

                        Spacer()
                    }
                    .padding(.horizontal, Theme.contentPadding)
                    .padding(.vertical, 12)
                    .background(tagColor.opacity(0.1))

                    // Todo items with unified background color
                    LazyVStack(spacing: 0) {
                        ForEach(todos) { todo in
                            TodoItemView(todoList: todoList, todo: todo, isTop5: false, groupColor: tagColor)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .background(
                ZStack {
                    Theme.cardBackground
                    tagColor.opacity(0.04)
                }
            )
            .cornerRadius(Theme.cornerRadiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                    .stroke(tagColor.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.vertical, 6)
    }
}

// Context-based section view (replaces TodoListSection)
struct ContextTodoSection: View {
    @ObservedObject var todoList: TodoList
    let section: ContextSection
    let todos: [Todo]
    var isTop5: Bool = false

    var body: some View {
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Section header with colored accent
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

                    // Clear Today button
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
                        .help("Remove #today tag from all items")
                    }
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.vertical, 12)
                .background(
                    section.color.opacity(section.id == "today" || section.id == "urgent" ? 0.1 : 0.06)
                )

                // Colored line under header
                Rectangle()
                    .fill(section.color.opacity(0.5))
                    .frame(height: 2)

                // Todo items - with section background color
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

struct TagListView: View {
    @ObservedObject var todoList: TodoList
    @Binding var selectedTag: String?
    @State private var showingExportAlert = false
    @State private var exportMessage = ""
    @State private var editingTag: String? = nil
    @State private var editedTagName: String = ""

    // Pre-compute todos grouped by tag to avoid O(n*m) filtering
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
            // Update all todos that have this tag
            for todo in todoList.todos {
                if todo.tags.contains(oldTag) {
                    var updatedTags = todo.tags
                    if let index = updatedTags.firstIndex(of: oldTag) {
                        updatedTags[index] = newTag
                        todoList.updateTodo(todo, withTags: updatedTags)
                    }
                }
            }

            // Update the tag in the todoList's allTags
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

// Add a resizable bar between columns with visual feedback
struct ResizableBar: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            // Wider invisible hit area
            Rectangle()
                .fill(Color.clear)
                .frame(width: 12)
                .contentShape(Rectangle())

            // Visible indicator - always show subtle line
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
