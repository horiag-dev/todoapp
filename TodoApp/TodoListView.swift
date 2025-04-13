import SwiftUI
import AppKit

struct MarkdownEditor: View {
    let text: String
    @ObservedObject var todoList: TodoList
    
    private func processLines() -> [(isList: Bool, content: String)] {
        let lines = text.components(separatedBy: .newlines)
        var result: [(isList: Bool, content: String)] = []
        var currentListItems: [String] = []
        
        for line in lines {
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                currentListItems.append(String(line.dropFirst(2)))
            } else {
                if !currentListItems.isEmpty {
                    result.append((true, currentListItems.joined(separator: "\n")))
                    currentListItems.removeAll()
                }
                if !line.isEmpty {
                    result.append((false, line))
                }
            }
        }
        
        if !currentListItems.isEmpty {
            result.append((true, currentListItems.joined(separator: "\n")))
        }
        
        return result
    }
    
    private func renderContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let processedLines = processLines()
            
            ForEach(processedLines.indices, id: \.self) { index in
                let item = processedLines[index]
                
                if item.isList {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(item.content.components(separatedBy: .newlines), id: \.self) { listItem in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(try! AttributedString(markdown: listItem))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } else {
                    Text(try! AttributedString(markdown: item.content))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(8)
    }
    
    var body: some View {
        ScrollView {
            renderContent()
        }
        .background(Color(NSColor.textBackgroundColor)) // Adapts to light/dark mode
        .cornerRadius(8)
    }
}

struct TodoListView: View {
    @ObservedObject var todoList: TodoList
    @State private var selectedTag: String?
    @State private var newTodoTitle = ""
    @State private var newTodoPriority: Priority = .normal
    @State private var showingTagManagement = false
    @State private var selectedTags: Set<String> = []
    @State private var leftColumnWidth: CGFloat = 300
    @State private var middleColumnWidth: CGFloat = 300
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar - Compact version
            HStack(spacing: 8) {
                // File Management - Simplified
                Button(action: { todoList.openFile() }) {
                    Image(systemName: "doc")
                }
                .help("Open existing todo file")
                
                Button(action: { todoList.createNewFile() }) {
                    Image(systemName: "doc.badge.plus")
                }
                .help("Create new todo file")
                
                Divider()
                    .frame(height: 20)
                
                // New Todo Input - Simplified
                TextField("New todo", text: $newTodoTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit(createTodo)
                
                Button(action: { showingTagManagement = true }) {
                    Image(systemName: "tag")
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showingTagManagement) {
                    TagSelectionSheet(
                        todoList: todoList,
                        selectedTags: $selectedTags,
                        isPresented: $showingTagManagement
                    )
                }
                
                Menu {
                    Button(action: { newTodoPriority = .urgent }) {
                        Label("Urgent", systemImage: "exclamationmark.circle.fill")
                    }
                    Button(action: { newTodoPriority = .normal }) {
                        Label("Normal", systemImage: "circle.fill")
                    }
                    Button(action: { newTodoPriority = .whenTime }) {
                        Label("When there's time", systemImage: "circle")
                    }
                } label: {
                    Image(systemName: newTodoPriority.icon)
                        .foregroundColor(newTodoPriority.color)
                }
                
                Button(action: createTodo) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(newTodoTitle.isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.windowBackgroundColor))
            
            // Main Content with Resizable Columns
            HStack(spacing: 0) {
                // Left Column - Goals and Top 5
                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            // Goals Section
                            VStack(alignment: .leading, spacing: Theme.itemSpacing) {
                                Text("Goals")
                                    .font(Theme.titleFont)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, Theme.contentPadding)
                                    .padding(.vertical, Theme.contentPadding)
                                    .background(Color(.windowBackgroundColor))
                                
                                MarkdownEditor(text: todoList.goals, todoList: todoList)
                                    .padding(.horizontal, Theme.contentPadding)
                            }
                            .frame(height: geometry.size.height * 0.75)
                            
                            Divider()
                            
                            // Top 5 Week Section
                            VStack(alignment: .leading, spacing: Theme.itemSpacing) {
                                Text("Top 5 Week")
                                    .font(Theme.titleFont)
                                    .padding(.horizontal, Theme.contentPadding)
                                
                                MarkdownEditor(text: todoList.bigThingsMarkdown, todoList: todoList)
                                    .padding(.horizontal, Theme.contentPadding)
                            }
                            .padding(.vertical, Theme.contentPadding)
                            .frame(height: geometry.size.height * 0.25)
                        }
                    }
                }
                .frame(width: leftColumnWidth)
                .background(Theme.leftColumnGradient)
                
                // Resizable divider
                ResizableBar(width: $leftColumnWidth, minWidth: 200, maxWidth: 500)
                
                Divider()
                
                // Middle Column - Tags
                VStack(spacing: Theme.itemSpacing) {
                    Text("Tags")
                        .font(Theme.titleFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.contentPadding)
                        .padding(.vertical, Theme.contentPadding)
                        .background(Color(.windowBackgroundColor))
                    
                    TagListView(todoList: todoList, selectedTag: $selectedTag)
                }
                .frame(width: middleColumnWidth)
                .background(Theme.middleColumnGradient)
                
                // Resizable divider
                ResizableBar(width: $middleColumnWidth, minWidth: 200, maxWidth: 500)
                
                Divider()
                
                // Right Column - Todos (fills remaining space)
                VStack(spacing: Theme.itemSpacing) {
                    Text("Todos")
                        .font(Theme.titleFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.contentPadding)
                        .padding(.vertical, Theme.contentPadding)
                        .background(Color(.windowBackgroundColor))
                    
                    ScrollView {
                        TodoListSections(todoList: todoList)
                    }
                }
                .background(Theme.rightColumnGradient)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    private func createTodo() {
        if !newTodoTitle.isEmpty {
            let todo = Todo(
                title: newTodoTitle,
                isCompleted: false,
                tags: Array(selectedTags),
                priority: newTodoPriority
            )
            todoList.addTodo(todo)
            newTodoTitle = ""
            selectedTags.removeAll()
            newTodoPriority = .normal
        }
    }
}

struct FileManagementControls: View {
    @ObservedObject var todoList: TodoList
    
    var body: some View {
        HStack {
            if let filePath = todoList.selectedFile?.path {
                Text(filePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No file selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { todoList.createNewFile() }) {
                Image(systemName: "doc.badge.plus")
            }
            .help("Create new todo file")
            
            Button(action: { todoList.openFile() }) {
                Image(systemName: "doc")
            }
            .help("Open existing todo file")
        }
        .padding()
    }
}

struct NewTodoInput: View {
    @ObservedObject var todoList: TodoList
    @Binding var newTodoTitle: String
    @Binding var newTodoPriority: Priority
    @Binding var showingTagManagement: Bool
    @Binding var selectedTags: Set<String>
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("New todo", text: $newTodoTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit(createTodo)
                
                Button(action: { showingTagManagement = true }) {
                    Image(systemName: "tag")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showingTagManagement) {
                    TagSelectionSheet(
                        todoList: todoList,
                        selectedTags: $selectedTags,
                        isPresented: $showingTagManagement
                    )
                }
                
                Menu {
                    Button(action: { newTodoPriority = .urgent }) {
                        Label("Urgent", systemImage: "exclamationmark.circle.fill")
                    }
                    Button(action: { newTodoPriority = .normal }) {
                        Label("Normal", systemImage: "circle.fill")
                    }
                    Button(action: { newTodoPriority = .whenTime }) {
                        Label("When there's time", systemImage: "circle")
                    }
                } label: {
                    Image(systemName: newTodoPriority.icon)
                        .foregroundColor(newTodoPriority.color)
                }
                
                Button(action: createTodo) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(newTodoTitle.isEmpty)
            }
            
            if !selectedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(selectedTags), id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 30)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }
    
    private func createTodo() {
        if !newTodoTitle.isEmpty {
            let todo = Todo(
                title: newTodoTitle,
                isCompleted: false,
                tags: Array(selectedTags),
                priority: newTodoPriority
            )
            todoList.addTodo(todo)
            newTodoTitle = ""
            selectedTags.removeAll()
            newTodoPriority = .normal
        }
    }
}

struct TodoListSections: View {
    @ObservedObject var todoList: TodoList
    
    private func filterAndSortTodos(for priority: Priority) -> [Todo] {
        let filteredTodos = todoList.todos.filter { $0.priority == priority && !$0.isCompleted }
        
        return filteredTodos.sorted { todo1, todo2 in
            let todo1HasPriorityTags = todo1.tags.contains("urgent") || todo1.tags.contains("today")
            let todo2HasPriorityTags = todo2.tags.contains("urgent") || todo2.tags.contains("today")
            
            if todo1HasPriorityTags == todo2HasPriorityTags {
                return false
            }
            
            return todo1HasPriorityTags
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach([Priority.urgent, Priority.normal, Priority.whenTime], id: \.self) { priority in
                let todos = filterAndSortTodos(for: priority)
                
                if !todos.isEmpty {
                    TodoListSection(todoList: todoList, priority: priority, todos: todos)
                }
            }
            
            // Completed section
            let completedTodos = todoList.todos.filter { $0.isCompleted }
            if !completedTodos.isEmpty {
                TodoListSection(todoList: todoList, priority: nil, todos: completedTodos)
            }
            
            // Deleted section
            if !todoList.deletedTodos.isEmpty {
                DisclosureGroup(
                    isExpanded: $todoList.isDeletedSectionCollapsed,
                    content: {
                        ForEach(todoList.deletedTodos) { todo in
                            HStack {
                                Text(todo.title)
                                    .strikethrough()
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { todoList.restoreTodo(todo) }) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .foregroundColor(.blue)
                                }
                                Button(action: { todoList.permanentlyDeleteTodo(todo) }) {
                                    Image(systemName: "trash.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, Theme.contentPadding)
                        }
                    },
                    label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("🗑️ Deleted Items")
                            Text("(\(todoList.deletedTodos.count))")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, Theme.contentPadding)
                    }
                )
                .padding(.vertical, Theme.itemSpacing)
                .background(Theme.background)
            }
        }
        .padding(.vertical)
    }
}

struct TodoListSection: View {
    let todoList: TodoList
    let priority: Priority?
    let todos: [Todo]
    
    var title: String {
        if let priority = priority {
            switch priority {
            case .urgent:
                return "🔴 Urgent"
            case .normal:
                return "🔵 Normal"
            case .whenTime:
                return "⚪ When there's time"
            }
        } else {
            return "✅ Completed"
        }
    }
    
    var body: some View {
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: Theme.itemSpacing) {
                HStack {
                    Text(title)
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.text)
                    Spacer()
                    
                    if priority == nil { // This is the completed section
                        Button(action: { todoList.moveAllCompletedToDeleted() }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Move to Deleted")
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.contentPadding)
                
                ForEach(todos) { todo in
                    TodoItemView(todoList: todoList, todo: todo)
                }
            }
            .padding(.vertical, Theme.itemSpacing)
            .background(Theme.background)
            .contentShape(Rectangle())
            .onTapGesture {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
}

struct TagListView: View {
    @ObservedObject var todoList: TodoList
    @Binding var selectedTag: String?
    @State private var showingExportAlert = false
    @State private var exportMessage = ""
    @State private var editingTag: String? = nil
    @State private var editedTagName: String = ""
    
    var body: some View {
        List {
            ForEach(todoList.allTags, id: \.self) { tag in
                Section(header: 
                    HStack {
                        if editingTag == tag {
                            TextField("Tag name", text: $editedTagName, onCommit: {
                                updateTagName(from: tag, to: editedTagName)
                            })
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onExitCommand {
                                editingTag = nil
                            }
                        } else {
                            Text(tag)
                                .onTapGesture(count: 2) {
                                    editingTag = tag
                                    editedTagName = tag
                                }
                        }
                        
                        Spacer()
                        
                        Button(action: { exportTodos(for: tag) }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Export to Notes")
                    }
                ) {
                    ForEach(todoList.todos.filter { $0.tags.contains(tag) }) { todo in
                        SimpleTodoItemView(todo: todo, todoList: todoList)
                    }
                }
            }
        }
        .listStyle(.inset)
        .alert("Export to Notes", isPresented: $showingExportAlert) {
            Button("Copy to Clipboard") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(exportMessage, forType: .string)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The todos have been formatted for Notes. Would you like to copy them to the clipboard?")
        }
    }
    
    private func updateTagName(from oldTag: String, to newTag: String) {
        if !newTag.isEmpty && newTag != oldTag {
            // Update all todos that have this tag
            for todo in todoList.todos {
                if todo.tags.contains(oldTag) {
                    var updatedTags = todo.tags
                    if let index = updatedTags.firstIndex(of: oldTag) {
                        updatedTags[index] = newTag
                        todoList.updateTodo(todo, withTags: updatedTags)
                    }
                }
            }
            
            // Update the tag in the todoList's allTags
            todoList.renameTag(from: oldTag, to: newTag)
        }
        
        editingTag = nil
    }
    
    private func exportTodos(for tag: String) {
        let todos = todoList.todos.filter { $0.tags.contains(tag) }
        var formattedText = "# \(tag)\n\n"
        
        for todo in todos {
            let checkbox = todo.isCompleted ? "- [x]" : "- [ ]"
            formattedText += "\(checkbox) \(todo.title)\n"
        }
        
        exportMessage = formattedText
        showingExportAlert = true
    }
}

struct SimpleTodoItemView: View {
    let todo: Todo
    @ObservedObject var todoList: TodoList
    
    var body: some View {
        HStack {
            Button(action: { todoList.toggleTodo(todo) }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? .green : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(todo.title)
                .strikethrough(todo.isCompleted)
                .foregroundColor(todo.isCompleted ? .gray : .primary)
            
            Spacer()
            
            Image(systemName: todo.priority.icon)
                .foregroundColor(todo.priority.color)
        }
        .padding(.vertical, 4)
    }
}

// Add a resizable bar between columns
struct ResizableBar: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var isResizing = false
    
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newWidth = width + value.translation.width
                        width = min(max(minWidth, newWidth), maxWidth)
                    }
            )
    }
} 