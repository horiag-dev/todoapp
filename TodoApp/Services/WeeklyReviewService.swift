import Foundation

// MARK: - Models

enum ReviewSuggestionType: String, Codable {
    case rephrase
    case addTags = "add_tags"
    case removeTags = "remove_tags"
    case changePriority = "change_priority"
    case moveToToday = "move_to_today"
    case removeFromToday = "remove_from_today"
}

struct ReviewSuggestion: Identifiable {
    let id: UUID
    let todoId: UUID
    let todoTitle: String
    let type: ReviewSuggestionType
    let reason: String
    var newTitle: String?
    var tagsToAdd: [String]?
    var tagsToRemove: [String]?
    var newPriority: String?
    var isAccepted: Bool

    init(
        id: UUID = UUID(),
        todoId: UUID,
        todoTitle: String,
        type: ReviewSuggestionType,
        reason: String,
        newTitle: String? = nil,
        tagsToAdd: [String]? = nil,
        tagsToRemove: [String]? = nil,
        newPriority: String? = nil,
        isAccepted: Bool = true
    ) {
        self.id = id
        self.todoId = todoId
        self.todoTitle = todoTitle
        self.type = type
        self.reason = reason
        self.newTitle = newTitle
        self.tagsToAdd = tagsToAdd
        self.tagsToRemove = tagsToRemove
        self.newPriority = newPriority
        self.isAccepted = isAccepted
    }
}

struct GoalInsight: Identifiable {
    let id = UUID()
    let type: GoalInsightType
    let title: String
    let detail: String
}

enum GoalInsightType: String {
    case noTodos = "no_todos"         // Goal with no supporting todos
    case suggestGoal = "suggest_goal" // Cluster of todos suggesting an unstated goal
    case misaligned = "misaligned"    // Todos that don't support any goal
}

struct WeeklyReviewResult {
    let summary: String
    let suggestions: [ReviewSuggestion]
    let goalInsights: [GoalInsight]
}

enum WeeklyReviewError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(Int, String)
    case parseError(String)
    case noTodos

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured. Add your Claude API key in Settings."
        case .invalidResponse: return "Received invalid response from the API."
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .parseError(let msg): return "Failed to parse AI response: \(msg)"
        case .noTodos: return "No todos to review."
        }
    }
}

// MARK: - Service

class WeeklyReviewService {
    static let shared = WeeklyReviewService()

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let modelID = "claude-opus-4-6"
    private let maxTokens = 4096

    private init() {}

    func performReview(
        todos: [Todo],
        top5Todos: [Todo],
        goals: String,
        bigThings: [String],
        availableTags: [String]
    ) async throws -> WeeklyReviewResult {
        let incompleteTodos = todos.filter { !$0.isCompleted }
        guard !incompleteTodos.isEmpty else {
            throw WeeklyReviewError.noTodos
        }

        guard let apiKey = APIKeyManager.shared.getAPIKey() else {
            throw WeeklyReviewError.noAPIKey
        }

        if APIKeyManager.shared.isDemoMode {
            return await demoReview(todos: incompleteTodos)
        }

        let prompt = buildPrompt(
            todos: incompleteTodos,
            top5Todos: top5Todos,
            goals: goals,
            bigThings: bigThings,
            availableTags: availableTags
        )

        let request = try buildRequest(apiKey: apiKey, prompt: prompt)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeeklyReviewError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WeeklyReviewError.apiError(httpResponse.statusCode, errorBody)
        }

        return try parseResponse(data, todos: incompleteTodos)
    }

    // MARK: - Private

    private func buildPrompt(
        todos: [Todo],
        top5Todos: [Todo],
        goals: String,
        bigThings: [String],
        availableTags: [String]
    ) -> String {
        // Serialize todos as JSON lines
        var todoLines: [String] = []
        for todo in todos {
            let section = todo.priority.rawValue
            let tags = todo.tags
            let escapedTitle = todo.title.replacingOccurrences(of: "\"", with: "\\\"")
            let tagsJSON = tags.map { "\"\($0)\"" }.joined(separator: ", ")
            todoLines.append(
                "  {\"todo_id\": \"\(todo.id.uuidString)\", \"title\": \"\(escapedTitle)\", \"section\": \"\(section)\", \"tags\": [\(tagsJSON)]}"
            )
        }

        let contexts = ContextConfigManager.shared.contexts
        let contextDescriptions = contexts.map { ctx -> String in
            switch ctx.id.lowercased() {
            case "prep": return "  - #\(ctx.id): meeting preparation, pre-meeting tasks, agendas"
            case "reply": return "  - #\(ctx.id): emails to send, messages to respond to, follow-ups"
            case "deep": return "  - #\(ctx.id): focused work requiring concentration - coding, writing, research"
            case "waiting": return "  - #\(ctx.id): blocked items, waiting on someone else"
            default: return "  - #\(ctx.id): \(ctx.name)"
            }
        }.joined(separator: "\n")

        let bigThingsText = bigThings.isEmpty
            ? "(None set)"
            : bigThings.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let top5Text = top5Todos.isEmpty
            ? "(None set)"
            : top5Todos.map { "- \($0.title)" }.joined(separator: "\n")

        let existingTagsList = availableTags.isEmpty ? "(none)" : availableTags.joined(separator: ", ")

        return """
        You are a productivity coach doing a weekly review of someone's todo list.
        Your job is to help them clean up, reorganize, and sharpen their task list for maximum clarity and alignment with their goals.

        ## Their Goals
        \(goals.isEmpty ? "(No goals set)" : goals)

        ## Big Things for the Week
        \(bigThingsText)

        ## Top 5 Priorities
        \(top5Text)

        ## Available Context Tags
        \(contextDescriptions)

        ## All Existing Tags in Use
        \(existingTagsList)

        ## Current Incomplete Todos
        [\(todoLines.joined(separator: ",\n"))]

        ## Your Task
        Review each incomplete todo and suggest improvements. You may suggest MULTIPLE changes for the same todo (each as a separate suggestion). Only suggest changes that would genuinely help. Focus on the most impactful improvements.

        Types of suggestions you can make:
        - **rephrase**: Fix grammar, typos, vagueness, or make the title more actionable and specific. Provide "new_title".
        - **add_tags**: Add context tags that fit the work type. Provide "tags_to_add" array. Only use tags from the existing tags or context tags listed above.
        - **remove_tags**: Remove tags that don't fit. Provide "tags_to_remove" array.
        - **change_priority**: Move to a different priority section. Provide "new_priority" ("today", "thisWeek", "urgent", or "normal"). Consider alignment with goals and top 5.
        - **move_to_today**: This todo should be done today (changes priority to Today). No extra fields needed.
        - **remove_from_today**: This todo doesn't need to be done today (changes priority to This Week). No extra fields needed.

        Rules:
        - Reference todos by their exact todo_id from the list above.
        - Only use tags that already exist in the available tags list or context tags listed above.
        - Do NOT suggest new todos. Only modify existing ones.
        - Focus on alignment with goals and priorities.
        - Be concise in reasons (1 sentence max).
        - Suggest between 5 and 20 changes total, focusing on the most impactful.
        - For todos currently in "Today" that aren't urgent or time-sensitive, suggest removing from today.
        - For poorly worded todos, always suggest a rephrase.

        ## Goal Alignment Analysis
        Also analyze the alignment between goals and todos. Provide 2-5 insights:
        - **no_todos**: A stated goal that has NO supporting todos — it's being neglected.
        - **suggest_goal**: A cluster of todos that suggests an unstated goal the user might want to add.
        - **misaligned**: Todos that don't clearly support any stated goal — they may be distractions.

        Each insight has: "type" (no_todos, suggest_goal, or misaligned), "title" (short label), "detail" (1 sentence explanation).

        Respond with ONLY valid JSON (no markdown code fences, no extra text):
        {"summary": "Brief 1-2 sentence assessment.", "suggestions": [{"todo_id": "uuid", "todo_title": "original title", "type": "rephrase", "reason": "Why", "new_title": "Better title", "tags_to_add": null, "tags_to_remove": null, "new_priority": null}], "goal_insights": [{"type": "no_todos", "title": "Goal name", "detail": "Explanation"}]}
        """
    }

    private func buildRequest(apiKey: String, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(_ data: Data, todos: [Todo]) throws -> WeeklyReviewResult {
        // Extract text from Claude API response envelope
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw WeeklyReviewError.parseError("Invalid API response structure")
        }

        // Clean markdown code fences if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let jsonStart = cleaned.range(of: "{"),
               let jsonEnd = cleaned.range(of: "}", options: .backwards) {
                cleaned = String(cleaned[jsonStart.lowerBound...jsonEnd.upperBound])
            }
        }

        guard let jsonData = cleaned.data(using: .utf8),
              let resultDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw WeeklyReviewError.parseError("Could not parse JSON from response")
        }

        let summary = resultDict["summary"] as? String ?? "Review complete."

        // Build a lookup map for todo IDs
        let todoMap = Dictionary(uniqueKeysWithValues: todos.map { ($0.id.uuidString, $0) })

        var suggestions: [ReviewSuggestion] = []

        if let suggestionsArray = resultDict["suggestions"] as? [[String: Any]] {
            for dict in suggestionsArray {
                guard let todoIdStr = dict["todo_id"] as? String,
                      let typeStr = dict["type"] as? String,
                      let type = ReviewSuggestionType(rawValue: typeStr),
                      let reason = dict["reason"] as? String else {
                    continue
                }

                // Validate the todo ID exists
                let todoId: UUID
                let todoTitle: String
                if let uuid = UUID(uuidString: todoIdStr), let todo = todoMap[todoIdStr] {
                    todoId = uuid
                    todoTitle = todo.title
                } else if let displayTitle = dict["todo_title"] as? String {
                    // Fallback: try to match by title
                    if let matched = todos.first(where: { $0.title == displayTitle }) {
                        todoId = matched.id
                        todoTitle = matched.title
                    } else {
                        continue // Skip unmatched suggestions
                    }
                } else {
                    continue
                }

                let suggestion = ReviewSuggestion(
                    todoId: todoId,
                    todoTitle: todoTitle,
                    type: type,
                    reason: reason,
                    newTitle: dict["new_title"] as? String,
                    tagsToAdd: dict["tags_to_add"] as? [String],
                    tagsToRemove: dict["tags_to_remove"] as? [String],
                    newPriority: dict["new_priority"] as? String
                )
                suggestions.append(suggestion)
            }
        }

        // Parse goal insights
        var goalInsights: [GoalInsight] = []
        if let insightsArray = resultDict["goal_insights"] as? [[String: Any]] {
            for dict in insightsArray {
                guard let typeStr = dict["type"] as? String,
                      let type = GoalInsightType(rawValue: typeStr),
                      let title = dict["title"] as? String,
                      let detail = dict["detail"] as? String else {
                    continue
                }
                goalInsights.append(GoalInsight(type: type, title: title, detail: detail))
            }
        }

        return WeeklyReviewResult(summary: summary, suggestions: suggestions, goalInsights: goalInsights)
    }

    // MARK: - Demo Mode

    private func demoReview(todos: [Todo]) async -> WeeklyReviewResult {
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        var suggestions: [ReviewSuggestion] = []
        let sampleTodos = Array(todos.prefix(8))

        for (index, todo) in sampleTodos.enumerated() {
            let isToday = todo.priority == .today

            switch index % 5 {
            case 0:
                suggestions.append(ReviewSuggestion(
                    todoId: todo.id,
                    todoTitle: todo.title,
                    type: .rephrase,
                    reason: "Making this more specific and actionable.",
                    newTitle: "Review and finalize: \(todo.title)"
                ))
            case 1:
                let contexts = ContextConfigManager.shared.contexts
                if let ctx = contexts.first {
                    suggestions.append(ReviewSuggestion(
                        todoId: todo.id,
                        todoTitle: todo.title,
                        type: .addTags,
                        reason: "This looks like it fits the \(ctx.name) context.",
                        tagsToAdd: [ctx.id]
                    ))
                }
            case 2:
                suggestions.append(ReviewSuggestion(
                    todoId: todo.id,
                    todoTitle: todo.title,
                    type: .changePriority,
                    reason: "This aligns with your top priorities for the week.",
                    newPriority: "thisWeek"
                ))
            case 3:
                if isToday {
                    suggestions.append(ReviewSuggestion(
                        todoId: todo.id,
                        todoTitle: todo.title,
                        type: .removeFromToday,
                        reason: "This isn't time-sensitive — can be done later this week."
                    ))
                } else {
                    suggestions.append(ReviewSuggestion(
                        todoId: todo.id,
                        todoTitle: todo.title,
                        type: .moveToToday,
                        reason: "This is time-sensitive and should be tackled today."
                    ))
                }
            case 4:
                if !todo.tags.isEmpty {
                    suggestions.append(ReviewSuggestion(
                        todoId: todo.id,
                        todoTitle: todo.title,
                        type: .removeTags,
                        reason: "This tag doesn't seem to fit the task.",
                        tagsToRemove: [todo.tags[0]]
                    ))
                }
            default:
                break
            }

            // Add extra suggestions for the first 3 todos to demo grouping
            if index < 3 {
                if index % 5 != 0 {
                    suggestions.append(ReviewSuggestion(
                        todoId: todo.id,
                        todoTitle: todo.title,
                        type: .rephrase,
                        reason: "Making this more actionable and specific.",
                        newTitle: "Action: \(todo.title)"
                    ))
                }
                if index % 5 != 2 {
                    suggestions.append(ReviewSuggestion(
                        todoId: todo.id,
                        todoTitle: todo.title,
                        type: .changePriority,
                        reason: "Consider reprioritizing based on your goals.",
                        newPriority: "urgent"
                    ))
                }
            }
        }

        let demoInsights: [GoalInsight] = [
            GoalInsight(type: .noTodos, title: "Health & Fitness", detail: "You have goals around health but no todos supporting them this week."),
            GoalInsight(type: .suggestGoal, title: "Team Communication", detail: "Several todos involve meetings and follow-ups — consider adding a communication goal."),
            GoalInsight(type: .misaligned, title: "Unrelated Tasks", detail: "A few todos don't clearly map to any of your stated goals and may be distractions.")
        ]

        return WeeklyReviewResult(
            summary: "Your todos are generally well-organized but several items could use clearer phrasing and better priority alignment with your goals. Consider focusing deep work items earlier in the week.",
            suggestions: suggestions,
            goalInsights: demoInsights
        )
    }
}
