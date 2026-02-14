import SwiftUI

// MARK: - Grouping Model

struct SuggestionGroup: Identifiable {
    let id: UUID // todoId
    let todoTitle: String
    let suggestionIndices: [Int]
}

// MARK: - Weekly Review View

struct WeeklyReviewView: View {
    @Binding var isPresented: Bool
    @ObservedObject var todoList: TodoList

    @State private var suggestions: [ReviewSuggestion] = []
    @State private var goalInsights: [GoalInsight] = []
    @State private var summary: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var loadingProgress: Double = 0.0
    @State private var loadingTimer: Timer? = nil

    private var acceptedCount: Int {
        suggestions.filter { $0.isAccepted }.count
    }

    private var affectedTodoCount: Int {
        Set(suggestions.filter { $0.isAccepted }.map { $0.todoId }).count
    }

    private var groupedSuggestions: [SuggestionGroup] {
        var indexMap: [UUID: [Int]] = [:]
        var titleMap: [UUID: String] = [:]
        var order: [UUID] = []

        for (index, suggestion) in suggestions.enumerated() {
            if indexMap[suggestion.todoId] == nil {
                order.append(suggestion.todoId)
                titleMap[suggestion.todoId] = suggestion.todoTitle
            }
            indexMap[suggestion.todoId, default: []].append(index)
        }

        return order.compactMap { todoId in
            guard let indices = indexMap[todoId],
                  let title = titleMap[todoId] else { return nil }
            return SuggestionGroup(id: todoId, todoTitle: title, suggestionIndices: indices)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                reviewHeader
                Divider()

                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else {
                    resultsView
                }

                Divider()
                reviewFooter
            }
            .frame(width: 680)
            .frame(minHeight: 400, maxHeight: 800)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusLg)
                    .fill(Theme.cardBackground)
                    .shadow(color: Theme.Shadow.hoverColor, radius: Theme.Shadow.hoverRadius, y: Theme.Shadow.hoverY)
            )
        }
        .task {
            await fetchReview()
        }
    }

    // MARK: - Header

    private var reviewHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 18))
                    .foregroundColor(.purple)
                Text("Weekly Review")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.text)
            }

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.secondaryBackground))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wand.and.stars")
                .font(.system(size: 32))
                .foregroundColor(.purple.opacity(0.6))

            Text("Analyzing your todos...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.secondaryText)

            // Progress bar
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.secondaryBackground)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.7), .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * loadingProgress, height: 6)
                            .animation(.easeOut(duration: 0.4), value: loadingProgress)
                    }
                }
                .frame(height: 6)

                Text(loadingStepText)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText.opacity(0.7))
                    .animation(.easeInOut(duration: 0.3), value: loadingStepText)
            }
            .frame(width: 280)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(24)
        .onAppear { startLoadingTimer() }
        .onDisappear { stopLoadingTimer() }
    }

    private var loadingStepText: String {
        if loadingProgress < 0.2 {
            return "Reading your goals and priorities..."
        } else if loadingProgress < 0.45 {
            return "Reviewing each todo for clarity..."
        } else if loadingProgress < 0.7 {
            return "Checking alignment with your goals..."
        } else if loadingProgress < 0.85 {
            return "Generating suggestions..."
        } else {
            return "Almost done..."
        }
    }

    private func startLoadingTimer() {
        loadingProgress = 0.0
        // Tick every 0.5s, fill to ~90% over ~15s (30 ticks × 0.03 = 0.9)
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                if loadingProgress < 0.9 {
                    loadingProgress += 0.03
                }
            }
        }
    }

    private func stopLoadingTimer() {
        loadingTimer?.invalidate()
        loadingTimer = nil
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Review Failed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.text)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") {
                Task { await fetchReview() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(24)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Summary banner
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.quote")
                    .font(.system(size: 12))
                    .foregroundColor(.purple.opacity(0.7))
                    .padding(.top, 2)
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.06))

            ScrollView {
                LazyVStack(spacing: 12) {
                    // Goal insights section
                    if !goalInsights.isEmpty {
                        GoalInsightsSection(insights: goalInsights)
                    }

                    // Grouped suggestion cards
                    ForEach(groupedSuggestions) { group in
                        GroupedSuggestionCard(
                            group: group,
                            suggestions: $suggestions
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Footer

    private var reviewFooter: some View {
        HStack {
            if !isLoading && errorMessage == nil {
                Text("\(acceptedCount) changes across \(affectedTodoCount) todos")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }

            Spacer()

            Button(action: dismiss) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .fill(Theme.secondaryBackground)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            if !isLoading && errorMessage == nil {
                Button(action: applyChanges) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("Apply \(acceptedCount) Changes")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .fill(acceptedCount > 0 ? Theme.accent : Theme.accent.opacity(0.4))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(acceptedCount == 0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func fetchReview() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await WeeklyReviewService.shared.performReview(
                todos: todoList.todos,
                top5Todos: todoList.top5Todos,
                goals: todoList.goals,
                bigThings: todoList.bigThings,
                availableTags: todoList.allTags
            )
            await MainActor.run {
                self.loadingProgress = 1.0
                self.stopLoadingTimer()
            }
            // Brief pause at 100% before showing results
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                self.suggestions = result.suggestions
                self.goalInsights = result.goalInsights
                self.summary = result.summary
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.stopLoadingTimer()
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func applyChanges() {
        let accepted = suggestions.filter { $0.isAccepted }

        for suggestion in accepted {
            guard let todoIndex = todoList.todos.firstIndex(where: { $0.id == suggestion.todoId }) else {
                continue
            }

            var todo = todoList.todos[todoIndex]

            switch suggestion.type {
            case .rephrase:
                if let newTitle = suggestion.newTitle, !newTitle.isEmpty {
                    todo.title = newTitle
                }
            case .addTags:
                if let tags = suggestion.tagsToAdd {
                    for tag in tags where !todo.tags.contains(tag) {
                        todo.tags.append(tag)
                    }
                }
            case .removeTags:
                if let tags = suggestion.tagsToRemove {
                    todo.tags.removeAll { tags.contains($0) }
                }
            case .changePriority, .moveToToday, .removeFromToday:
                if let priorityStr = suggestion.newPriority {
                    switch priorityStr {
                    case "today": todo.priority = .today
                    case "thisWeek": todo.priority = .thisWeek
                    case "urgent": todo.priority = .urgent
                    case "normal": todo.priority = .normal
                    default: break
                    }
                } else {
                    switch suggestion.type {
                    case .moveToToday: todo.priority = .today
                    case .removeFromToday: todo.priority = .thisWeek
                    default: break
                    }
                }
            }

            todoList.updateTodo(todo)
        }

        dismiss()
    }

    private func dismiss() {
        withAnimation(Theme.Animation.quickFade) {
            isPresented = false
        }
    }
}

// MARK: - Grouped Suggestion Card

struct GroupedSuggestionCard: View {
    let group: SuggestionGroup
    @Binding var suggestions: [ReviewSuggestion]

    private var allAccepted: Bool {
        group.suggestionIndices.allSatisfy { suggestions[$0].isAccepted }
    }

    private var anyAccepted: Bool {
        group.suggestionIndices.contains { suggestions[$0].isAccepted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: todo title + select-all toggle
            HStack(spacing: 8) {
                Button(action: toggleAll) {
                    Image(systemName: allAccepted ? "checkmark.circle.fill" : (anyAccepted ? "minus.circle.fill" : "circle"))
                        .font(.system(size: 18))
                        .foregroundColor(allAccepted ? .green : (anyAccepted ? .orange : Theme.secondaryText.opacity(0.4)))
                }
                .buttonStyle(PlainButtonStyle())

                Text(group.todoTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)

                Spacer()

                Text("\(group.suggestionIndices.count) \(group.suggestionIndices.count == 1 ? "change" : "changes")")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.secondaryBackground)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ForEach(Array(group.suggestionIndices.enumerated()), id: \.element) { offset, index in
                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.5)

                SuggestionRow(suggestion: $suggestions[index])
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .fill(anyAccepted ? Theme.secondaryBackground : Theme.secondaryBackground.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .stroke(anyAccepted ? Color.purple.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .animation(Theme.Animation.quickFade, value: allAccepted)
    }

    private func toggleAll() {
        let newValue = !allAccepted
        for index in group.suggestionIndices {
            suggestions[index].isAccepted = newValue
        }
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    @Binding var suggestion: ReviewSuggestion

    private var typeIcon: String {
        switch suggestion.type {
        case .rephrase: return "pencil.line"
        case .addTags: return "tag.fill"
        case .removeTags: return "tag.slash"
        case .changePriority: return "arrow.up.arrow.down"
        case .moveToToday: return "sun.max.fill"
        case .removeFromToday: return "sun.min"
        }
    }

    private var typeLabel: String {
        switch suggestion.type {
        case .rephrase: return "Rephrase"
        case .addTags: return "Add Tags"
        case .removeTags: return "Remove Tags"
        case .changePriority: return "Priority"
        case .moveToToday: return "Move to Today"
        case .removeFromToday: return "Remove from Today"
        }
    }

    private var typeColor: Color {
        switch suggestion.type {
        case .rephrase: return .blue
        case .addTags: return .green
        case .removeTags: return .orange
        case .changePriority: return .purple
        case .moveToToday: return Color(red: 0.95, green: 0.6, blue: 0.1)
        case .removeFromToday: return .gray
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Per-suggestion accept/reject
            Button(action: { suggestion.isAccepted.toggle() }) {
                Image(systemName: suggestion.isAccepted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(suggestion.isAccepted ? .green : Theme.secondaryText.opacity(0.4))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                // Type badge
                HStack(spacing: 4) {
                    Image(systemName: typeIcon)
                        .font(.system(size: 9))
                    Text(typeLabel)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(typeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(typeColor.opacity(0.12))
                )

                // Editable content
                editableContent

                // Reason
                Text(suggestion.reason)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .opacity(suggestion.isAccepted ? 1.0 : 0.5)
        .animation(Theme.Animation.quickFade, value: suggestion.isAccepted)
    }

    // MARK: - Editable Content per Type

    @ViewBuilder
    private var editableContent: some View {
        switch suggestion.type {
        case .rephrase:
            rephraseEditor
        case .addTags:
            addTagsEditor
        case .removeTags:
            removeTagsEditor
        case .changePriority, .moveToToday, .removeFromToday:
            priorityPicker
        }
    }

    // MARK: Rephrase Editor

    private var rephraseEditor: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(Theme.secondaryText)

            if suggestion.isAccepted {
                TextField(
                    "New title",
                    text: Binding(
                        get: { suggestion.newTitle ?? "" },
                        set: { suggestion.newTitle = $0 }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
            } else {
                Text(suggestion.newTitle ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue.opacity(0.5))
                    .lineLimit(2)
            }
        }
    }

    // MARK: Priority Picker

    private var currentPriorityString: String {
        if let p = suggestion.newPriority {
            return p
        }
        switch suggestion.type {
        case .moveToToday: return "today"
        case .removeFromToday: return "thisWeek"
        default: return "normal"
        }
    }

    private var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            if suggestion.isAccepted {
                HStack(spacing: 4) {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        let priorityStr = priorityKeyFor(priority)
                        let isSelected = currentPriorityString == priorityStr

                        Button(action: {
                            suggestion.newPriority = priorityStr
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: priority.icon)
                                    .font(.system(size: 8))
                                Text(priority.rawValue)
                                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                            }
                            .foregroundColor(isSelected ? .white : priority.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? priority.color : priority.color.opacity(0.12))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Text("Move to:")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                    Text(priorityDisplayLabel(currentPriorityString))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                }
            }
        }
    }

    private func priorityKeyFor(_ priority: Priority) -> String {
        switch priority {
        case .today: return "today"
        case .thisWeek: return "thisWeek"
        case .urgent: return "urgent"
        case .normal: return "normal"
        }
    }

    private func priorityDisplayLabel(_ key: String) -> String {
        switch key {
        case "today": return "Today"
        case "thisWeek": return "This Week"
        case "urgent": return "Urgent"
        case "normal": return "Normal"
        default: return key
        }
    }

    // MARK: Add Tags Editor

    private var addTagsEditor: some View {
        HStack(spacing: 4) {
            Text("Add:")
                .font(.system(size: 10))
                .foregroundColor(Theme.secondaryText)

            if let tags = suggestion.tagsToAdd, !tags.isEmpty {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 2) {
                        TagPillView(tag: tag, size: .small, interactive: false)

                        if suggestion.isAccepted {
                            Button(action: {
                                suggestion.tagsToAdd?.removeAll { $0 == tag }
                                if suggestion.tagsToAdd?.isEmpty == true {
                                    suggestion.isAccepted = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.secondaryText.opacity(0.5))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            } else {
                Text("(none)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText.opacity(0.5))
            }
        }
    }

    // MARK: Remove Tags Editor

    private var removeTagsEditor: some View {
        HStack(spacing: 4) {
            Text("Remove:")
                .font(.system(size: 10))
                .foregroundColor(Theme.secondaryText)

            if let tags = suggestion.tagsToRemove, !tags.isEmpty {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 2) {
                        Text("#\(tag)")
                            .font(.system(size: 10))
                            .strikethrough()
                            .foregroundColor(.red.opacity(0.7))

                        if suggestion.isAccepted {
                            Button(action: {
                                suggestion.tagsToRemove?.removeAll { $0 == tag }
                                if suggestion.tagsToRemove?.isEmpty == true {
                                    suggestion.isAccepted = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.secondaryText.opacity(0.5))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            } else {
                Text("(none)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText.opacity(0.5))
            }
        }
    }
}

// MARK: - Goal Insights Section

struct GoalInsightsSection: View {
    let insights: [GoalInsight]
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(Theme.Animation.quickFade) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)

                    Text("Goal Alignment")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)

                    Text("\(insights.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.orange))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(insights) { insight in
                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.5)

                        GoalInsightRow(insight: insight)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .fill(Color.orange.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

struct GoalInsightRow: View {
    let insight: GoalInsight

    private var icon: String {
        switch insight.type {
        case .noTodos: return "exclamationmark.triangle"
        case .suggestGoal: return "lightbulb"
        case .misaligned: return "arrow.triangle.branch"
        }
    }

    private var iconColor: Color {
        switch insight.type {
        case .noTodos: return .red
        case .suggestGoal: return .yellow
        case .misaligned: return .orange
        }
    }

    private var typeLabel: String {
        switch insight.type {
        case .noTodos: return "No Todos"
        case .suggestGoal: return "Suggested Goal"
        case .misaligned: return "Misaligned"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(typeLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(iconColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(iconColor.opacity(0.12))
                        )

                    Text(insight.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.text)
                }

                Text(insight.detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
