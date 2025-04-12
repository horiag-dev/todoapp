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
    @State private var newBigThingTitle = ""
    @State private var newTodoPriority: Priority = .normal
    @State private var showingTagManagement = false
    @State private var selectedTags: Set<String> = []
    
    var body: some View {
        NavigationView {
            // Left panel - Goals
            VStack(spacing: 0) {
                FileManagementControls(todoList: todoList)
                    .padding(Theme.contentPadding)
                
                VStack(alignment: .leading, spacing: Theme.itemSpacing) {
                    HStack {
                        Text("Goals")
                            .font(Theme.titleFont)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.contentPadding)
                    
                    MarkdownEditor(text: todoList.goals, todoList: todoList)
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal, Theme.contentPadding)
                }
                .padding(.vertical, Theme.itemSpacing)
                .background(Theme.background)
            }
            .frame(minWidth: 300, maxWidth: .infinity)
            
            // Middle panel - Tags (25%)
            VStack(spacing: 0) {
                HStack {
                    Text("Tags & Categories")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
                
                TagListView(todoList: todoList, selectedTag: $selectedTag)
                    .background(Color(NSColor.underPageBackgroundColor)) // System background that adapts to dark/light mode
            }
            .frame(minWidth: 300, maxWidth: .infinity)
            
            // Right panel - Todos and Big Things (50%)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Todos & Big Things")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    BigThingsSection(todoList: todoList)
                    Divider()
                    NewTodoInput(
                        todoList: todoList,
                        newTodoTitle: $newTodoTitle,
                        newTodoPriority: $newTodoPriority,
                        showingTagManagement: $showingTagManagement,
                        selectedTags: $selectedTags
                    )
                    ScrollView {
                        TodoListSections(todoList: todoList)
                    }
                }
                .background(Color(.windowBackgroundColor))
            }
            .frame(minWidth: 300, maxWidth: .infinity)
        }
        .navigationTitle("Todo List")
        .frame(minWidth: 900, minHeight: 600)
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

struct BigThingsSection: View {
    @ObservedObject var todoList: TodoList
    @State private var newBigThingTitle: String = ""
    @State private var isAddingNew = false
    @State private var height: CGFloat = 140 // Smaller default height for 3-4 items
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("🎯 Big Things for the Week")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { isAddingNew = true }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $isAddingNew) {
                    VStack(spacing: 8) {
                        TextField("Add a big thing for the week", text: $newBigThingTitle)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit { addBigThing() }
                        
                        HStack {
                            Button("Cancel") {
                                isAddingNew = false
                                newBigThingTitle = ""
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button("Add") {
                                addBigThing()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(newBigThingTitle.isEmpty)
                        }
                    }
                    .padding()
                    .frame(width: 300)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            if !todoList.bigThings.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(todoList.bigThings.indices, id: \.self) { index in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 25, alignment: .leading)
                                
                                Text(todoList.bigThings[index])
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Spacer()
                                
                                Button(action: { todoList.removeBigThing(at: index) }) {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal)
                            .background(Color(.windowBackgroundColor))
                            .onDrag {
                                return NSItemProvider(object: String(index) as NSString)
                            }
                            .onDrop(of: [.text], delegate: BigThingDropDelegate(
                                todoList: todoList,
                                fromIndex: index
                            ))
                        }
                    }
                }
                .frame(height: height)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            height = max(80, min(400, height + value.translation.height))
                        }
                )
            } else {
                Spacer()
                    .frame(height: height)
            }
        }
        .padding(.vertical, 4)
        .background(Color(.windowBackgroundColor))
    }
    
    private func addBigThing() {
        if !newBigThingTitle.isEmpty {
            todoList.addBigThing(newBigThingTitle)
            newBigThingTitle = ""
            isAddingNew = false
        }
    }
}

struct BigThingDropDelegate: DropDelegate {
    let todoList: TodoList
    let fromIndex: Int
    
    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        
        item.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
            if let data = data as? Data,
               let str = String(data: data, encoding: .utf8),
               let toIndex = Int(str) {
                DispatchQueue.main.async {
                    moveItem(from: fromIndex, to: toIndex)
                }
            }
        }
        
        return true
    }
    
    private func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < todoList.bigThings.count,
              destinationIndex >= 0 && destinationIndex < todoList.bigThings.count else {
            return
        }
        
        var items = todoList.bigThings
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: destinationIndex)
        todoList.bigThings = items
        todoList.saveTodos()
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