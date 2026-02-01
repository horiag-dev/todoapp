import SwiftUI
import AppKit

// MARK: - Quick Add Mode
enum QuickAddMode: String, CaseIterable {
    case reply = "Reply to"
    case prep = "Prep for"
    case deep = "Deep work"
    case custom = "Custom"

    var icon: String {
        switch self {
        case .reply: return "arrowshape.turn.up.left.fill"
        case .prep: return "calendar"
        case .deep: return "brain.head.profile"
        case .custom: return "pencil"
        }
    }

    var contextTag: String? {
        switch self {
        case .reply: return "reply"
        case .prep: return "prep"
        case .deep: return "deep"
        case .custom: return nil
        }
    }

    var color: Color {
        switch self {
        case .reply: return Color(red: 0.5, green: 0.8, blue: 0.5)
        case .prep: return Color(red: 0.4, green: 0.6, blue: 0.9)
        case .deep: return Color(red: 0.7, green: 0.5, blue: 0.9)
        case .custom: return .gray
        }
    }
}

// MARK: - Quick Add Panel View
struct QuickAddPanelView: View {
    @ObservedObject var todoList: TodoList
    @Binding var isPresented: Bool

    @State private var clipboardText: String = ""
    @State private var selectedMode: QuickAddMode = .reply
    @State private var customTitle: String = ""
    @State private var additionalTags: Set<String> = []
    @FocusState private var isTitleFocused: Bool

    var finalTitle: String {
        if selectedMode == .custom {
            return customTitle.isEmpty ? clipboardText : customTitle
        }
        return "\(selectedMode.rawValue): \(clipboardText)"
    }

    // Get frequently used tags (excluding context tags already shown as modes)
    var frequentTags: [String] {
        let contextTags = Set(["reply", "prep", "deep", "waiting"])
        return todoList.allTags
            .filter { !contextTags.contains($0.lowercased()) }
            .prefix(8)
            .map { $0 }
    }

    // Get all tags that will be applied
    func getAllTags() -> [String] {
        var tags: [String] = []
        if let contextTag = selectedMode.contextTag {
            tags.append(contextTag)
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
                // Clipboard content preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("From clipboard:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(clipboardText.isEmpty ? "No text in clipboard" : clipboardText)
                        .font(.system(size: 13))
                        .foregroundColor(clipboardText.isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }

                // Mode selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add as:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(QuickAddMode.allCases, id: \.self) { mode in
                            Button(action: {
                                selectedMode = mode
                                if mode == .custom {
                                    isTitleFocused = true
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 11))
                                    Text(mode.rawValue)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(selectedMode == mode ? .white : mode.color)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedMode == mode ? mode.color : mode.color.opacity(0.15))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(mode.color, lineWidth: selectedMode == mode ? 0 : 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // Custom title (only for custom mode)
                if selectedMode == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom title:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        TextField("Enter todo title...", text: $customTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .focused($isTitleFocused)
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
                        }
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
                .disabled(clipboardText.isEmpty && customTitle.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .onAppear {
            loadClipboard()
        }
    }

    private func loadClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            // Clean up the clipboard text - remove extra whitespace
            clipboardText = string.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .first ?? string
        }
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
        hostingView.frame = CGRect(x: 0, y: 0, width: 420, height: 380)

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
