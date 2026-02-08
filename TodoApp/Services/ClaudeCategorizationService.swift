import Foundation

/// Result of context suggestion from Claude
struct TagSuggestion: Codable {
    let context: String?      // Context tag (prep, reply, deep, waiting)

    init(context: String? = nil) {
        self.context = context
    }
}

/// Service for calling Claude API to auto-categorize todos
class ClaudeCategorizationService {
    static let shared = ClaudeCategorizationService()

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let modelID = "claude-sonnet-4-20250514"  // Better quality for categorization

    private init() {}

    // Available context tags for categorization (from configuration)
    var contextTags: [String] {
        ContextConfigManager.shared.contextTags
    }

    /// Suggests tags for a todo item using Claude
    /// - Parameters:
    ///   - todoText: The todo item text to analyze
    ///   - existingTags: Tags already in use in the app
    ///   - goalSections: Names of goal sections for context
    /// - Returns: Tag suggestion with context and additional tags
    func suggestTags(
        todoText: String,
        existingTags: [String] = [],
        goalSections: [String] = []
    ) async throws -> TagSuggestion {
        guard let apiKey = APIKeyManager.shared.getAPIKey() else {
            throw CategorizationError.noAPIKey
        }

        // Demo mode: return a smart mock response without calling the API
        if APIKeyManager.shared.isDemoMode {
            return await demoSuggestTags(todoText: todoText)
        }

        let prompt = buildPrompt(
            todoText: todoText,
            existingTags: existingTags,
            goalSections: goalSections
        )

        let request = try buildRequest(apiKey: apiKey, prompt: prompt)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CategorizationError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw CategorizationError.apiError(httpResponse.statusCode, errorBody)
            }
            throw CategorizationError.apiError(httpResponse.statusCode, "Unknown error")
        }

        return try parseResponse(data)
    }

    /// Demo mode: suggests a context tag based on keyword matching
    private func demoSuggestTags(todoText: String) async -> TagSuggestion {
        // Simulate a brief network delay so the UI feels realistic
        try? await Task.sleep(nanoseconds: 600_000_000)

        let text = todoText.lowercased()
        let contexts = ContextConfigManager.shared.contexts
        let contextIDs = Set(contexts.map { $0.id.lowercased() })

        // Keyword-to-context mapping for realistic demo suggestions
        let keywords: [(words: [String], context: String)] = [
            (["meet", "agenda", "standup", "sync", "call", "1:1", "prepare", "presentation", "slides", "brief"], "prep"),
            (["email", "reply", "respond", "message", "follow up", "slack", "send", "write back", "ping"], "reply"),
            (["code", "build", "design", "research", "write", "analyze", "debug", "implement", "refactor", "focus", "draft", "review code"], "deep"),
            (["waiting", "blocked", "pending", "depends", "approval", "sign off", "hear back", "response from"], "waiting"),
        ]

        for entry in keywords {
            // Only suggest if this context actually exists in the user's config
            guard contextIDs.contains(entry.context) else { continue }
            for word in entry.words {
                if text.contains(word) {
                    return TagSuggestion(context: entry.context)
                }
            }
        }

        // Fallback: suggest the first available context
        if let first = contexts.first {
            return TagSuggestion(context: first.id)
        }

        return TagSuggestion()
    }

    // MARK: - Private Methods

    private func buildPrompt(todoText: String, existingTags: [String], goalSections: [String]) -> String {
        let contexts = ContextConfigManager.shared.contexts
        let contextTagsList = contexts.map { $0.id }.joined(separator: ", ")

        // Build context descriptions
        let contextDescriptions = contexts.map { context -> String in
            switch context.id.lowercased() {
            case "prep": return "- \(context.id): meeting preparation, pre-meeting tasks, agendas, materials to prepare before a meeting"
            case "reply": return "- \(context.id): emails to send, messages to respond to, follow-ups to write"
            case "deep": return "- \(context.id): focused work requiring concentration - coding, writing, research, analysis"
            case "waiting": return "- \(context.id): blocked items, waiting on someone else, pending responses"
            default: return "- \(context.id): tasks related to \(context.name.lowercased())"
            }
        }.joined(separator: "\n")

        return """
        Categorize this todo into ONE context category.

        Todo: "\(todoText)"

        Available contexts: \(contextTagsList)
        \(contextDescriptions)

        Rules:
        - Choose exactly ONE context that best fits, or null if none fit well
        - Only use the exact context names listed above

        Respond with ONLY this JSON format:
        {"context": "prep"}

        Or if no context fits:
        {"context": null}
        """
    }

    private func buildRequest(apiKey: String, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 100,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(_ data: Data) throws -> TagSuggestion {
        // Parse the Claude API response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw CategorizationError.parseError("Invalid response structure")
        }

        // Extract JSON from the response text - handle potential markdown wrapping
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if cleanedText.hasPrefix("```") {
            if let jsonStart = cleanedText.range(of: "{"),
               let jsonEnd = cleanedText.range(of: "}", options: .backwards) {
                cleanedText = String(cleanedText[jsonStart.lowerBound...jsonEnd.upperBound])
            }
        }

        // Try to parse the JSON response
        guard let jsonData = cleanedText.data(using: .utf8),
              let suggestionDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            // If parsing fails, return empty suggestion
            return TagSuggestion()
        }

        let context = suggestionDict["context"] as? String

        // Validate context is one of our known context tags
        let validContext = context.flatMap { ctx in
            contextTags.contains(ctx.lowercased()) ? ctx.lowercased() : nil
        }

        return TagSuggestion(context: validContext)
    }
}

// MARK: - Errors

enum CategorizationError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your Claude API key in Settings."
        case .invalidResponse:
            return "Received invalid response from API"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .parseError(let message):
            return "Failed to parse response: \(message)"
        }
    }
}
