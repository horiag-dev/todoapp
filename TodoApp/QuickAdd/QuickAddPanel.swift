import SwiftUI
import AppKit

// MARK: - Quick Add Panel View
struct QuickAddPanelView: View {
    @ObservedObject var todoList: TodoList
    @ObservedObject var contextManager = ContextConfigManager.shared
    @Binding var isPresented: Bool

    @State private var todoText: String = ""
    @State private var selectedContextId: String? = nil  // nil means no context prefix
    @State private var additionalTags: Set<String> = []
    @State private var newTagText: String = ""
    @FocusState private var isTextFocused: Bool
    @FocusState private var isNewTagFocused: Bool

    // Urgency tags that should always be available
    private let urgencyTags = ["thisweek", "urgent"]

    var selectedContext: ContextConfig? {
        guard let id = selectedContextId else { return nil }
        return contextManager.contexts.first { $0.id == id }
    }

    var finalTitle: String {
        if let context = selectedContext {
            return "\(context.name) for: \(todoText)"
        }
        return todoText
    }

    // Get frequently used tags (excluding context tags already shown as modes)
    var frequentTags: [String] {
        let contextTagsSet = Set(contextManager.contextTags)
        let urgencySet = Set(urgencyTags)

        // Start with urgency tags, then add user's tags
        var result = urgencyTags

        let userTags = todoList.allTags
            .filter { tag in
                let lowered = tag.lowercased()
                return !contextTagsSet.contains(lowered) && !urgencySet.contains(lowered)
            }
            .prefix(5)

        result.append(contentsOf: userTags)
        return result
    }

    // Get all tags that will be applied
    func getAllTags() -> [String] {
        var tags: [String] = []
        if let context = selectedContext {
            tags.append(context.id)
        }
        tags.append(contentsOf: additionalTags.sorted())
        return tags
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                Text("Quick Add Todo")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("⌘⇧T")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            VStack(spacing: 16) {
                // Todo text input (editable)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Todo:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    TextField("What do you need to do?", text: $todoText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .focused($isTextFocused)
                }

                // Mode selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add as:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Dynamic context buttons from ContextConfigManager
                            ForEach(contextManager.contexts) { context in
                                let isSelected = selectedContextId == context.id
                                Button(action: {
                                    selectedContextId = context.id
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: context.icon)
                                            .font(.system(size: 11))
                                        Text("\(context.name) for")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(isSelected ? .white : context.color)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? context.color : context.color.opacity(0.15))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(context.color, lineWidth: isSelected ? 0 : 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            // No context button (plain text, no prefix)
                            Button(action: {
                                selectedContextId = nil
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "text.cursor")
                                        .font(.system(size: 11))
                                    Text("Plain")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(selectedContextId == nil ? .white : .gray)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedContextId == nil ? Color.gray : Color.gray.opacity(0.15))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray, lineWidth: selectedContextId == nil ? 0 : 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // Additional tags (compact picker)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add tags:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            // Show frequently used tags as quick-add chips
                            ForEach(frequentTags, id: \.self) { tag in
                                let isSelected = additionalTags.contains(tag)
                                let tagColor = Theme.colorForTag(tag)
                                Button(action: {
                                    if isSelected {
                                        additionalTags.remove(tag)
                                    } else {
                                        additionalTags.insert(tag)
                                    }
                                }) {
                                    Text("#\(tag)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(isSelected ? tagColor : tagColor.opacity(0.12))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(tagColor.opacity(0.5), lineWidth: isSelected ? 0 : 1)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            // Show any custom-added tags that aren't in frequent tags
                            ForEach(Array(additionalTags.filter { !frequentTags.contains($0) }), id: \.self) { tag in
                                let tagColor = Theme.colorForTag(tag)
                                Button(action: {
                                    additionalTags.remove(tag)
                                }) {
                                    HStack(spacing: 4) {
                                        Text("#\(tag)")
                                            .font(.system(size: 11, weight: .medium))
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(tagColor)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }

                    // Custom tag input
                    HStack(spacing: 8) {
                        TextField("Add custom tag...", text: $newTagText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                            .focused($isNewTagFocused)
                            .onSubmit {
                                addCustomTag()
                            }

                        Button(action: addCustomTag) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(newTagText.isEmpty ? .gray : .blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(newTagText.isEmpty)
                    }
                }

                // Preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("Will create:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(finalTitle)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        // Show all tags that will be added
                        let allTags = getAllTags()
                        if !allTags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(allTags, id: \.self) { tag in
                                    let tagColor = Theme.colorForTag(tag)
                                    Text("#\(tag)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(tagColor.opacity(0.12))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(16)

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: addTodo) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Todo")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(todoText.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .onAppear {
            loadClipboard()
            // Select first context by default
            if selectedContextId == nil, let firstContext = contextManager.contexts.first {
                selectedContextId = firstContext.id
            }
        }
    }

    private func loadClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            // Clean up the clipboard text - remove extra whitespace
            todoText = string.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .first ?? string
        }
        // Focus the text field
        isTextFocused = true
    }

    private func addCustomTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "-")
        guard !tag.isEmpty else { return }
        additionalTags.insert(tag)
        newTagText = ""
    }

    private func addTodo() {
        guard !finalTitle.isEmpty else { return }

        let todo = Todo(
            title: finalTitle,
            isCompleted: false,
            tags: getAllTags(),
            priority: .thisWeek
        )

        todoList.addTodo(todo)
        isPresented = false
    }
}

// MARK: - Quick Add Window Controller
class QuickAddWindowController: NSObject {
    static let shared = QuickAddWindowController()

    private var window: NSWindow?
    private var todoList: TodoList?

    func setup(todoList: TodoList) {
        self.todoList = todoList
    }

    func showQuickAddPanel() {
        guard let todoList = todoList else { return }

        // Close existing window if any
        window?.close()

        // Create the SwiftUI view
        let isPresented = Binding<Bool>(
            get: { self.window != nil },
            set: { if !$0 { self.closePanel() } }
        )

        let contentView = QuickAddPanelView(todoList: todoList, isPresented: isPresented)

        // Create a borderless window
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 420, height: 440)

        let window = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isFloatingPanel = true
        window.level = .floating
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2 + 100 // Slightly above center
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func closePanel() {
        window?.close()
        window = nil
    }
}
