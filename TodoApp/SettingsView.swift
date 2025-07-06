import SwiftUI

struct SettingsView: View {
    @ObservedObject var llmService: LLMService
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            
            // API Key Section
            VStack(alignment: .leading, spacing: 12) {
                Text("OpenAI API Configuration")
                    .font(.headline)
                
                Text("Enter your OpenAI API key to enable AI-powered todo refactoring and tag suggestions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onAppear {
                        apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
                    }
                
                HStack {
                    Button("Save API Key") {
                        saveAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Test Connection") {
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(apiKey.isEmpty)
                    
                    Spacer()
                }
                
                if let error = llmService.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(12)
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("How to get an API key:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Go to https://platform.openai.com/api-keys")
                    Text("2. Sign in or create an account")
                    Text("3. Click 'Create new secret key'")
                    Text("4. Copy the key and paste it above")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 400)
        .alert("Settings", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func saveAPIKey() {
        llmService.setAPIKey(apiKey)
        alertMessage = "API key saved successfully!"
        showingAlert = true
    }
    
    private func testConnection() {
        Task {
            let response = await llmService.refactorTodo("test todo")
            await MainActor.run {
                if response != nil {
                    alertMessage = "Connection successful! API key is working."
                } else {
                    alertMessage = "Connection failed. Please check your API key."
                }
                showingAlert = true
            }
        }
    }
} 