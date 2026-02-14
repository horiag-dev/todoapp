import SwiftUI

struct WeeklyReviewView: View {
    @Binding var isPresented: Bool
    @ObservedObject var todoList: TodoList

    @State private var suggestions: [ReviewSuggestion] = []
    @State private var summary: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    private var acceptedCount: Int {
        suggestions.filter { $0.isAccepted }.count
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Main card
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
            .frame(width: 620)
            .frame(minHeight: 400, maxHeight: 700)
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
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Analyzing your todos...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.secondaryText)
            Text("Claude is reviewing your tasks against your goals and priorities.")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(24)
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

            // Suggestion cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(suggestions.indices, id: \.self) { index in
                        SuggestionCardView(suggestion: $suggestions[index])
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
                Text("\(acceptedCount) of \(suggestions.count) changes selected")
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
                self.suggestions = result.suggestions
                self.summary = result.summary
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
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
                if let newTitle = suggestion.newTitle {
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
            case .changePriority:
                if let priorityStr = suggestion.newPriority {
                    switch priorityStr {
                    case "today": todo.priority = .today
                    case "thisWeek": todo.priority = .thisWeek
                    case "urgent": todo.priority = .urgent
                    case "normal": todo.priority = .normal
                    default: break
                    }
                }
            case .moveToToday:
                todo.priority = .today
            case .removeFromToday:
                todo.priority = .thisWeek
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

// MARK: - Suggestion Card

struct SuggestionCardView: View {
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
        HStack(alignment: .top, spacing: 12) {
            // Accept/reject toggle
            Button(action: { suggestion.isAccepted.toggle() }) {
                Image(systemName: suggestion.isAccepted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(suggestion.isAccepted ? .green : Theme.secondaryText.opacity(0.4))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                // Type badge + original title
                HStack(spacing: 6) {
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

                    Text(suggestion.todoTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                }

                // Change detail
                changeDetailView

                // Reason
                Text(suggestion.reason)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(suggestion.isAccepted ? Theme.secondaryBackground : Theme.secondaryBackground.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(suggestion.isAccepted ? typeColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .opacity(suggestion.isAccepted ? 1.0 : 0.6)
        .animation(Theme.Animation.quickFade, value: suggestion.isAccepted)
    }

    @ViewBuilder
    private var changeDetailView: some View {
        switch suggestion.type {
        case .rephrase:
            if let newTitle = suggestion.newTitle {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.secondaryText)
                    Text(newTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                        .lineLimit(2)
                }
            }
        case .addTags:
            if let tags = suggestion.tagsToAdd {
                HStack(spacing: 4) {
                    Text("Add:")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                    ForEach(tags, id: \.self) { tag in
                        TagPillView(tag: tag, size: .small, interactive: false)
                    }
                }
            }
        case .removeTags:
            if let tags = suggestion.tagsToRemove {
                HStack(spacing: 4) {
                    Text("Remove:")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10))
                            .strikethrough()
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
        case .changePriority:
            if let priority = suggestion.newPriority {
                HStack(spacing: 4) {
                    Text("Move to:")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                    Text(priorityLabel(priority))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(priorityColor(priority))
                }
            }
        case .moveToToday:
            HStack(spacing: 4) {
                Text("Move to")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
                TagPillView(tag: "today", size: .small, interactive: false)
            }
        case .removeFromToday:
            HStack(spacing: 4) {
                Text("Remove from")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
                Text("Today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func priorityLabel(_ priority: String) -> String {
        switch priority {
        case "thisWeek": return "This Week"
        case "urgent": return "Urgent"
        case "normal": return "Normal"
        default: return priority
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "thisWeek": return Color(red: 0.95, green: 0.5, blue: 0.0)
        case "urgent": return Color(red: 0.9, green: 0.75, blue: 0.0)
        default: return Theme.accent
        }
    }
}
