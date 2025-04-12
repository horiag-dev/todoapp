import SwiftUI

struct ContentView: View {
    @StateObject private var todoList = TodoList()
    
    var body: some View {
        TodoListView(todoList: todoList)
    }
} 