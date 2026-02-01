import SwiftUI

@main
struct TodoApp: App {
    @StateObject private var todoList = TodoList()
    @State private var showQuickAdd = false

    var body: some Scene {
        WindowGroup {
            TodoListView(todoList: todoList)
                .onAppear {
                    // Initialize quick add controller
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

        // Menu Bar Extra - always accessible
        MenuBarExtra("Todo Quick Add", systemImage: "checklist") {
            Button("Quick Add from Clipboard...") {
                QuickAddWindowController.shared.showQuickAddPanel()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Open Todo App") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title != "Quick Add" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
} 