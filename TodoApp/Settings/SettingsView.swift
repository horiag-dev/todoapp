import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var hasKey: Bool = false
    @State private var showingKey: Bool = false
    @State private var saveMessage: String = ""
    @State private var showSaveMessage: Bool = false
    @StateObject private var contextConfig = ContextConfigManager.shared
    @State private var editingContext: ContextConfig? = nil
    @State private var showingAddContext: Bool = false
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

                // Context Categories Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .foregroundColor(.purple)
                            Text("Context Categories")
                                .font(.headline)
                            Spacer()
                            Button(action: { showingAddContext = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Add new context")
                        }

                        Text("Configure the context tags used to organize your todos.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(contextConfig.contexts) { context in
                            HStack(spacing: 12) {
                                // Color indicator
                                Circle()
                                    .fill(context.color)
                                    .frame(width: 12, height: 12)

                                // Icon
                                Image(systemName: context.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(context.color)
                                    .frame(width: 20)

                                // Name
                                Text(context.name)
                                    .font(.system(size: 13, weight: .medium))

                                Text("#\(context.id)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Spacer()

                                // Edit button
                                Button(action: { editingContext = context }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())

                                // Delete button
                                Button(action: {
                                    if let index = contextConfig.contexts.firstIndex(where: { $0.id == context.id }) {
                                        contextConfig.removeContext(at: index)
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(context.color.opacity(0.1))
                            )
                        }

                        // Reset to defaults
                        Button(action: { contextConfig.resetToDefaults() }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Defaults")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
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

                    Text("Required for auto-categorization of todos. Your key is stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                        // Save button
                        Button(action: saveAPIKey) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Save")
                            }
                        }
                        .disabled(apiKey.isEmpty)

                        // Delete button (only if key exists)
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

                        // Status indicator
                        if hasKey {
                            Label("Key saved", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    // Save message feedback
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
                        Text("About Auto-Categorization")
                            .font(.headline)
                    }

                    Text("When enabled, the app uses Claude AI to suggest context tags for your todos. This helps organize tasks into categories like Meetings, Replies, Deep Work, and Waiting.")
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
        .frame(width: 500, height: 750)
        .onAppear {
            loadCurrentKey()
        }
        .sheet(item: $editingContext) { context in
            ContextEditSheet(context: context, isNew: false) { updatedContext in
                contextConfig.updateContext(updatedContext)
            }
        }
        .sheet(isPresented: $showingAddContext) {
            ContextEditSheet(context: ContextConfig(id: "", name: "", icon: "tag", color: .blue), isNew: true) { newContext in
                contextConfig.addContext(newContext)
            }
        }
    }

    private func loadCurrentKey() {
        hasKey = APIKeyManager.shared.hasAPIKey
        if hasKey {
            // Show masked key
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
            // Mask the displayed key
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

// Sheet for editing/adding a context
struct ContextEditSheet: View {
    @State var context: ContextConfig
    let isNew: Bool
    let onSave: (ContextConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    // Available icons to choose from
    private let availableIcons = [
        "calendar", "arrowshape.turn.up.left.fill", "brain.head.profile", "hourglass",
        "envelope", "phone", "person", "doc", "folder", "list.bullet", "checkmark.circle",
        "star", "flag", "bell", "bookmark", "tag", "paperclip", "link", "globe",
        "building.2", "briefcase", "creditcard", "cart", "house", "car"
    ]

    // Available colors
    private let availableColors: [Color] = [
        Color(red: 0.4, green: 0.6, blue: 0.9),   // Blue
        Color(red: 0.5, green: 0.8, blue: 0.5),   // Green
        Color(red: 0.7, green: 0.5, blue: 0.9),   // Purple
        Color(red: 0.6, green: 0.6, blue: 0.6),   // Gray
        Color(red: 0.9, green: 0.5, blue: 0.5),   // Red
        Color(red: 0.9, green: 0.7, blue: 0.3),   // Orange
        Color(red: 0.4, green: 0.8, blue: 0.8),   // Teal
        Color(red: 0.8, green: 0.5, blue: 0.7),   // Pink
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text(isNew ? "Add Context" : "Edit Context")
                .font(.headline)

            // ID (only editable for new)
            HStack {
                Text("Tag ID:")
                    .frame(width: 80, alignment: .trailing)
                if isNew {
                    TextField("e.g., meeting", text: $context.id)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text("#\(context.id)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // Name
            HStack {
                Text("Display Name:")
                    .frame(width: 80, alignment: .trailing)
                TextField("e.g., Meetings", text: $context.name)
                    .textFieldStyle(.roundedBorder)
            }

            // Icon picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon:")
                    .frame(width: 80, alignment: .trailing)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 8) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button(action: { context.icon = icon }) {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(context.icon == icon ? context.color.opacity(0.3) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(context.icon == icon ? context.color : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color:")

                HStack(spacing: 8) {
                    ForEach(availableColors, id: \.self) { color in
                        Button(action: {
                            context.colorHex = color.toHex() ?? "#808080"
                        }) {
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: context.color == color ? 3 : 0)
                                )
                                .shadow(color: context.color == color ? color.opacity(0.5) : .clear, radius: 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            // Preview
            HStack {
                Text("Preview:")
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: context.icon)
                        .foregroundColor(context.color)
                    Text(context.name.isEmpty ? "Context Name" : context.name)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(context.color.opacity(0.15))
                )
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button(isNew ? "Add" : "Save") {
                    onSave(context)
                    dismiss()
                }
                .disabled(context.id.isEmpty || context.name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 450)
    }
}

#Preview {
    SettingsView()
}
