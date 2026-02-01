import SwiftUI

@main
struct TodoApp: App {
    @StateObject private var todoList = TodoList()

    init() {
        // Setup will be called after todoList is initialized
    }

    var body: some Scene {
        WindowGroup {
            TodoListView(todoList: todoList)
                .onAppear {
                    // Initialize quick add panel with global hotkey (Cmd+Shift+T)
                    QuickAddWindowController.shared.setup(todoList: todoList)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // Add menu item for Quick Add
            CommandGroup(after: .newItem) {
                Button("Quick Add from Clipboard") {
                    QuickAddWindowController.shared.showQuickAddPanel()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
} 