import SwiftUI
import AppKit

// MARK: - Quick Add Panel View
struct QuickAddPanelView: View {
    @ObservedObject var todoList: TodoList
    @Binding var isPresented: Bool

    @State private var todoText: String = ""
    @State private var additionalTags: Set<String> = []
    @State private var newTagText: String = ""
    @FocusState private var isTextFocused: Bool
    @FocusState private var isNewTagFocused: Bool

    // Get frequently used tags
    var frequentTags: [String] {
        let urgencyTags = ["thisweek", "urgent"]
        let urgencySet = Set(urgencyTags)

        var result = urgencyTags

        let userTags = todoList.allTags
            .filter { tag in
                !urgencySet.contains(tag.lowercased())
            }
            .prefix(5)

        result.append(contentsOf: userTags)
        return result
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
                // Todo text input
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

                // Tags
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add tags:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
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
                        Text(todoText)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        let allTags = Array(additionalTags).sorted()
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
        }
    }

    private func loadClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            todoText = string.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .first ?? string
        }
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
        guard !todoText.isEmpty else { return }

        let todo = Todo(
            title: todoText,
            isCompleted: false,
            tags: Array(additionalTags).sorted(),
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

        window?.close()

        let isPresented = Binding<Bool>(
            get: { self.window != nil },
            set: { if !$0 { self.closePanel() } }
        )

        let contentView = QuickAddPanelView(todoList: todoList, isPresented: isPresented)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 420, height: 400)

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

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2 + 100
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
