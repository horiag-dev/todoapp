import SwiftUI

@main
struct TodoApp: App {
    @StateObject private var todoList = TodoList()
    
    var body: some Scene {
        WindowGroup {
            TodoListView(todoList: todoList)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
} 