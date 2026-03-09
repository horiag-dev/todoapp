import Foundation

/// Result of tag suggestion from Claude
struct TagSuggestion: Codable {
    let suggestedTag: String?

    init(suggestedTag: String? = nil) {
        self.suggestedTag = suggestedTag
    }
}

/// Service for calling Claude API to auto-categorize todos
class ClaudeCategorizationService {
    static let shared = ClaudeCategorizationService()

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let modelID = "claude-sonnet-4-20250514"

    private init() {}

    /// Suggests a tag for a todo item using Claude
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
            return await demoSuggestTags(todoText: todoText, existingTags: existingTags)
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

        return try parseResponse(data, existingTags: existingTags)
    }

    /// Demo mode: suggests a tag based on keyword matching
    private func demoSuggestTags(todoText: String, existingTags: [String]) async -> TagSuggestion {
        try? await Task.sleep(nanoseconds: 600_000_000)

        let text = todoText.lowercased()

        // Keyword-to-tag mapping for realistic demo suggestions
        let keywords: [(words: [String], tag: String)] = [
            (["meet", "standup", "sync", "call", "1:1"], "meeting"),
            (["email", "reply", "respond", "message", "slack"], "comms"),
            (["code", "build", "debug", "implement", "refactor"], "dev"),
            (["design", "mockup", "wireframe", "figma"], "design"),
            (["review", "feedback", "approve"], "review"),
            (["write", "draft", "blog", "doc"], "writing"),
            (["plan", "roadmap", "strategy"], "planning"),
            (["hire", "interview", "candidate"], "hiring"),
        ]

        let existingSet = Set(existingTags.map { $0.lowercased() })

        for entry in keywords {
            for word in entry.words {
                if text.contains(word) {
                    // Prefer matching an existing tag
                    if existingSet.contains(entry.tag) {
                        return TagSuggestion(suggestedTag: entry.tag)
                    }
                    return TagSuggestion(suggestedTag: entry.tag)
                }
            }
        }

        return TagSuggestion()
    }

    // MARK: - Private Methods

    private func buildPrompt(todoText: String, existingTags: [String], goalSections: [String]) -> String {
        let tagsList = existingTags.joined(separator: ", ")

        return """
        Suggest ONE tag for this todo item.

        Todo: "\(todoText)"

        Existing tags in use: \(tagsList)

        Rules:
        - Prefer an existing tag if one fits well
        - If no existing tag fits, suggest a short, descriptive new tag (1-2 words, lowercase)
        - If no tag makes sense, return null

        Respond with ONLY this JSON format:
        {"tag": "tagname"}

        Or if no tag fits:
        {"tag": null}
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

    private func parseResponse(_ data: Data, existingTags: [String]) throws -> TagSuggestion {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw CategorizationError.parseError("Invalid response structure")
        }

        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanedText.hasPrefix("```") {
            if let jsonStart = cleanedText.range(of: "{"),
               let jsonEnd = cleanedText.range(of: "}", options: .backwards) {
                cleanedText = String(cleanedText[jsonStart.lowerBound...jsonEnd.upperBound])
            }
        }

        guard let jsonData = cleanedText.data(using: .utf8),
              let suggestionDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return TagSuggestion()
        }

        let tag = suggestionDict["tag"] as? String

        return TagSuggestion(suggestedTag: tag)
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
