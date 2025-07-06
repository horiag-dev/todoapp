import Foundation

struct LLMResponse: Codable {
    let title: String
    let tags: [String]
    let priority: String
    let reasoning: String
}

class LLMService: ObservableObject {
    @Published var isProcessing = false
    @Published var lastError: String?
    
    private var apiKey: String {
        get {
            return UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        }
    }
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    init() {
        // API key is now retrieved dynamically from UserDefaults
    }
    
    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "openai_api_key")
        print("🔑 API key updated: \(String(key.prefix(10)))...")
    }
    
    func refactorTodo(_ originalTitle: String, existingTags: [String] = []) async -> LLMResponse? {
        guard !apiKey.isEmpty else {
            await MainActor.run {
                self.lastError = "OpenAI API key not set. Please configure it in settings."
            }
            return nil
        }
        
        await MainActor.run {
            self.isProcessing = true
            self.lastError = nil
        }
        
        let prompt = """
        You are a productivity assistant that helps users create well-structured todo items. 
        
        Given a todo title, please:
        1. Refactor the title to be clear, actionable, and specific
        2. Suggest relevant tags (3-5 tags max) based on the content
        3. Determine the appropriate priority level (urgent, normal, or whenTime)
        4. Provide brief reasoning for your suggestions
        
        Existing tags in the user's system: \(existingTags.joined(separator: ", "))
        
        Original todo: "\(originalTitle)"
        
        Respond with a JSON object in this exact format:
        {
            "title": "refactored title",
            "tags": ["tag1", "tag2", "tag3"],
            "priority": "urgent|normal|whenTime",
            "reasoning": "brief explanation of changes"
        }
        
        Guidelines:
        - Make titles action-oriented (start with verbs)
        - Use existing tags when relevant
        - Priority: urgent = time-sensitive/critical, normal = standard tasks, whenTime = low priority/backlog
        - Keep tags concise and relevant
        """
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": "You are a helpful productivity assistant that returns only valid JSON responses."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 500
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            var request = URLRequest(url: URL(string: baseURL)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = jsonData
            
            print("🔑 API Key (first 10 chars): \(String(apiKey.prefix(10)))...")
            print("📤 Sending request to OpenAI...")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    self.lastError = "Invalid response from server"
                    self.isProcessing = false
                }
                return nil
            }
            
            print("📥 Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ API Error: \(errorString)")
                
                await MainActor.run {
                    if httpResponse.statusCode == 401 {
                        self.lastError = "Invalid API key. Please check your OpenAI API key."
                    } else if httpResponse.statusCode == 429 {
                        self.lastError = "Rate limit exceeded. Please try again later."
                    } else if httpResponse.statusCode == 400 {
                        self.lastError = "Bad request. Please check your input."
                    } else {
                        self.lastError = "API request failed with status \(httpResponse.statusCode): \(errorString)"
                    }
                    self.isProcessing = false
                }
                return nil
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? ""
            print("📄 Full API Response: \(responseString)")
            
            // Parse the OpenAI response
            if let openAIResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
               let content = openAIResponse.choices.first?.message.content {
                
                print("🎯 Extracted content: \(content)")
                
                // Extract JSON from the content
                let jsonStart = content.firstIndex(of: "{")
                let jsonEnd = content.lastIndex(of: "}")
                
                if let start = jsonStart, let end = jsonEnd {
                    let jsonString = String(content[start...end])
                    print("🔍 Extracted JSON: \(jsonString)")
                    
                    if let jsonData = jsonString.data(using: .utf8),
                       let llmResponse = try? JSONDecoder().decode(LLMResponse.self, from: jsonData) {
                        await MainActor.run {
                            self.isProcessing = false
                        }
                        print("✅ Successfully parsed LLM response")
                        return llmResponse
                    } else {
                        print("❌ Failed to decode JSON response")
                    }
                } else {
                    print("❌ Could not find JSON brackets in response")
                }
            } else {
                print("❌ Failed to parse OpenAI response structure")
            }
            
            await MainActor.run {
                self.lastError = "Failed to parse LLM response. Check console for details."
                self.isProcessing = false
            }
            return nil
            
        } catch {
            print("❌ Network error: \(error)")
            await MainActor.run {
                self.lastError = "Network error: \(error.localizedDescription)"
                self.isProcessing = false
            }
            return nil
        }
    }
}

// OpenAI API response structures
struct OpenAIResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: Message
}

struct Message: Codable {
    let content: String
} 