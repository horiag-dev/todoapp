import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var hasKey: Bool = false
    @State private var showingKey: Bool = false
    @State private var saveMessage: String = ""
    @State private var showSaveMessage: Bool = false
    @StateObject private var appearanceManager = AppearanceManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.title2.bold())
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                }
                .padding(.bottom, 8)

                // Appearance Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "paintbrush.fill")
                                .foregroundColor(.blue)
                            Text("Appearance")
                                .font(.headline)
                        }

                        Text("Choose how the app looks. System follows your macOS appearance setting.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                Button(action: {
                                    appearanceManager.currentMode = mode
                                }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: mode.icon)
                                            .font(.system(size: 24))
                                            .foregroundColor(appearanceManager.currentMode == mode ? .white : .primary)

                                        Text(mode.rawValue)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(appearanceManager.currentMode == mode ? .white : .primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(appearanceManager.currentMode == mode ? Color.accentColor : Color.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(appearanceManager.currentMode == mode ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(8)
                }

                // API Key Section
                GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.orange)
                        Text("Claude API Key")
                            .font(.headline)
                    }

                    Text("Required for AI tag suggestions. Your key is stored securely in the macOS Keychain. Enter \"demo\" to try the feature without a real key.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if APIKeyManager.shared.isDemoMode {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Demo Mode Active")
                                .font(.caption.bold())
                            Text("- AI tagging uses sample responses instead of the live API.")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.1))
                        )
                    }

                    HStack {
                        if showingKey {
                            TextField("Enter API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("Enter API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showingKey.toggle() }) {
                            Image(systemName: showingKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(showingKey ? "Hide API key" : "Show API key")
                    }

                    HStack {
                        Button(action: saveAPIKey) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Save")
                            }
                        }
                        .disabled(apiKey.isEmpty)

                        if hasKey {
                            Button(action: deleteAPIKey) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Remove")
                                }
                                .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Spacer()

                        if hasKey {
                            Label("Key saved", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    if showSaveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundColor(saveMessage.contains("Error") ? .red : .green)
                            .transition(.opacity)
                    }
                }
                .padding(8)
            }

            // Info Section
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("About AI Tag Suggestions")
                            .font(.headline)
                    }

                    Text("When enabled, the app uses Claude AI to suggest tags for your todos. Right-click any todo and select \"Auto-tag with AI\" to get a suggestion.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link(destination: URL(string: "https://console.anthropic.com/")!) {
                        HStack {
                            Image(systemName: "arrow.up.right.square")
                            Text("Get an API key from Anthropic Console")
                        }
                        .font(.caption)
                    }
                }
                .padding(8)
            }
            }
            .padding(20)
        }
        .frame(width: 500, height: 550)
        .onAppear {
            loadCurrentKey()
        }
    }

    private func loadCurrentKey() {
        hasKey = APIKeyManager.shared.hasAPIKey
        if hasKey {
            if let key = APIKeyManager.shared.getAPIKey() {
                let prefix = String(key.prefix(8))
                let suffix = String(key.suffix(4))
                apiKey = "\(prefix)...\(suffix)"
            }
        }
    }

    private func saveAPIKey() {
        do {
            try APIKeyManager.shared.saveAPIKey(apiKey)
            hasKey = true
            showMessage("API key saved successfully")
            let prefix = String(apiKey.prefix(8))
            let suffix = String(apiKey.suffix(4))
            apiKey = "\(prefix)...\(suffix)"
        } catch {
            showMessage("Error: \(error.localizedDescription)")
        }
    }

    private func deleteAPIKey() {
        do {
            try APIKeyManager.shared.deleteAPIKey()
            hasKey = false
            apiKey = ""
            showMessage("API key removed")
        } catch {
            showMessage("Error: \(error.localizedDescription)")
        }
    }

    private func showMessage(_ message: String) {
        saveMessage = message
        withAnimation {
            showSaveMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showSaveMessage = false
            }
        }
    }
}

#Preview {
    SettingsView()
}
