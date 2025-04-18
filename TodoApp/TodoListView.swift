import SwiftUI
import AppKit

struct MarkdownEditor: View {
    let text: String
    @ObservedObject var todoList: TodoList
    
    private func processLines() -> [(isList: Bool, content: String, isNumbered: Bool, number: Int?, tags: [String])] {
        let lines = text.components(separatedBy: .newlines)
        var result: [(isList: Bool, content: String, isNumbered: Bool, number: Int?, tags: [String])] = []
        var currentListItems: [(content: String, tags: [String])] = []
        var currentNumberedItems: [(number: Int, content: String, tags: [String])] = []
        
        for line in lines {
            // Split content and tags
            let components = line.components(separatedBy: " #")
            let mainContent = components[0]
            let tags = components.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
            
            if mainContent.hasPrefix("- ") || mainContent.hasPrefix("* ") {
                let content = String(mainContent.dropFirst(2))
                currentListItems.append((content: content, tags: tags))
            } else if let match = mainContent.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let number = Int(mainContent[..<match.upperBound].trimmingCharacters(in: CharacterSet(charactersIn: ". "))) ?? 0
                let content = String(mainContent[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                currentNumberedItems.append((number: number, content: content, tags: tags))
            } else {
                if !currentListItems.isEmpty {
                    for item in currentListItems {
                        result.append((true, item.content, false, nil, item.tags))
                    }
                    currentListItems.removeAll()
                }
                if !currentNumberedItems.isEmpty {
                    for item in currentNumberedItems {
                        result.append((true, item.content, true, item.number, item.tags))
                    }
                    currentNumberedItems.removeAll()
                }
                if !mainContent.isEmpty {
                    result.append((false, mainContent, false, nil, tags))
                }
            }
        }
        
        if !currentListItems.isEmpty {
            for item in currentListItems {
                result.append((true, item.content, false, nil, item.tags))
            }
        }
        if !currentNumberedItems.isEmpty {
            for item in currentNumberedItems {
                result.append((true, item.content, true, item.number, item.tags))
            }
        }
        
        return result
    }
    
    private func TagView(tag: String) -> some View {
        let isSpecialTag = tag.lowercased() == "urgent" || tag.lowercased() == "today"
        let tagColor = Theme.colorForTag(tag)
        
        return Text("#\(tag)")
            .font(Theme.smallFont)
            .foregroundColor(isSpecialTag ? .white : Theme.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(isSpecialTag ? tagColor : tagColor.opacity(0.25))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(isSpecialTag ? Color.clear : tagColor.opacity(0.8), lineWidth: 1)
            )
    }
    
    private func renderContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let processedLines = processLines()
            
            ForEach(processedLines.indices, id: \.self) { index in
                let item = processedLines[index]
                
                if item.isList {
                    if item.isNumbered {
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(item.number ?? 0).")
                                .foregroundColor(.secondary)
                                .frame(width: 25, alignment: .trailing)
                            HStack {
                                Text(try! AttributedString(markdown: item.content))
                                if !item.tags.isEmpty {
                                    ForEach(item.tags, id: \.self) { tag in
                                        TagView(tag: tag)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                                .foregroundColor(.secondary)
                            HStack {
                                Text(try! AttributedString(markdown: item.content))
                                if !item.tags.isEmpty {
                                    ForEach(item.tags, id: \.self) { tag in
                                        TagView(tag: tag)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    HStack {
                        Text(try! AttributedString(markdown: item.content))
                        if !item.tags.isEmpty {
                            ForEach(item.tags, id: \.self) { tag in
                                TagView(tag: tag)
                            }
                        }
                    }
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
            // Top Bar - File Management
            HStack(spacing: 8) {
                Button(action: { todoList.openFile() }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Open existing todo file")
                
                Button(action: { todoList.createNewFile() }) {
                    Image(systemName: "doc.badge.plus")
                }
                .help("Create new todo file")

                Spacer()
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
                                    .background(Color(NSColor.textBackgroundColor))
                                
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
                        .background(Color(NSColor.textBackgroundColor))
                    
                    TagListView(todoList: todoList, selectedTag: $selectedTag)
                }
                .frame(width: middleColumnWidth)
                .background(Theme.middleColumnGradient)
                
                // Resizable divider
                ResizableBar(width: $middleColumnWidth, minWidth: 200, maxWidth: 500)
                
                Divider()
                
                // Right Column - Todos
                VStack(spacing: Theme.itemSpacing) {
                    VStack(spacing: Theme.itemSpacing) {
                        Text("Todos")
                            .font(Theme.titleFont)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.contentPadding)
                            .padding(.vertical, Theme.contentPadding)
                            .background(Color(NSColor.textBackgroundColor))
                        
                        // New Todo Input - Left aligned
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
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(Theme.cornerRadius)
                        .padding(.horizontal, Theme.contentPadding)
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
                Image(systemName: "folder.badge.plus")
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
    
    // Get all unique tags from the todo list
    private var availableTags: [String] {
        todoList.allTags.sorted()
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                TextField("New todo", text: $newTodoTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit(createTodo)
                
                // Quick priority buttons
                HStack(spacing: 8) {
                    Button(action: { newTodoPriority = .urgent }) {
                        Image(systemName: "flag.fill")
                            .foregroundColor(newTodoPriority == .urgent ? .red : .gray.opacity(0.3))
                            .imageScale(.medium)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Urgent")
                    
                    Button(action: { newTodoPriority = .normal }) {
                        Image(systemName: "flag")
                            .foregroundColor(newTodoPriority == .normal ? Theme.accent : .gray.opacity(0.3))
                            .imageScale(.medium)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Normal")
                    
                    Button(action: { newTodoPriority = .whenTime }) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(newTodoPriority == .whenTime ? Theme.secondaryText : .gray.opacity(0.3))
                            .imageScale(.medium)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("When there's time")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.secondaryBackground)
                .cornerRadius(8)
                
                // Tag management button
                Button(action: { showingTagManagement = true }) {
                    Image(systemName: "tag")
                        .foregroundColor(.blue)
                        .imageScale(.medium)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showingTagManagement) {
                    TagSelectionSheet(
                        todoList: todoList,
                        selectedTags: $selectedTags,
                        isPresented: $showingTagManagement
                    )
                }
                
                // Add todo button
                Button(action: createTodo) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .imageScale(.medium)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(newTodoTitle.isEmpty)
            }
            .padding(.horizontal, 12)
            
            // Quick tag buttons
            if !availableTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button(action: {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }) {
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(selectedTags.contains(tag) ? Color.blue.opacity(0.2) : Theme.secondaryBackground)
                                    .foregroundColor(selectedTags.contains(tag) ? .blue : Theme.text)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 30)
            }
            
            // Selected tags display
            if !selectedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedTags), id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.caption)
                                Button(action: { selectedTags.remove(tag) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .imageScale(.small)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 12)
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
        let filteredTodos = todoList.todos.filter { todo in
            if todo.isCompleted {
                return false
            }
            
            // Check if todo has urgent/today tags
            let hasUrgentTag = todo.tags.contains { $0.lowercased() == "urgent" || $0.lowercased() == "today" }
            
            switch priority {
            case .urgent:
                // Include todos with urgent priority OR urgent/today tags
                return todo.priority == .urgent || hasUrgentTag
            case .normal:
                // Only include normal priority todos WITHOUT urgent/today tags
                return todo.priority == .normal && !hasUrgentTag
            case .whenTime:
                // Only include whenTime priority todos WITHOUT urgent/today tags
                return todo.priority == .whenTime && !hasUrgentTag
            }
        }
        
        // Sort the filtered todos
        return filteredTodos.sorted { todo1, todo2 in
            // First, sort by urgent/today tags
            let todo1HasPriorityTags = todo1.tags.contains { $0.lowercased() == "urgent" || $0.lowercased() == "today" }
            let todo2HasPriorityTags = todo2.tags.contains { $0.lowercased() == "urgent" || $0.lowercased() == "today" }
            
            if todo1HasPriorityTags != todo2HasPriorityTags {
                return todo1HasPriorityTags
            }
            
            // Then, group by common tags
            let commonTags1 = Set(todo1.tags).intersection(todoList.allTags)
            let commonTags2 = Set(todo2.tags).intersection(todoList.allTags)
            
            if !commonTags1.isEmpty && !commonTags2.isEmpty {
                // If both todos have tags, sort by the first tag alphabetically
                let firstTag1 = commonTags1.sorted().first!
                let firstTag2 = commonTags2.sorted().first!
                
                if firstTag1 != firstTag2 {
                    return firstTag1 < firstTag2
                }
            } else if !commonTags1.isEmpty {
                return true // Todo with tags comes first
            } else if !commonTags2.isEmpty {
                return false // Todo with tags comes first
            }
            
            // Finally, sort alphabetically by title
            return todo1.title.localizedStandardCompare(todo2.title) == .orderedAscending
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach([Priority.urgent, Priority.normal, Priority.whenTime], id: \.self) { priority in
                let todos = filterAndSortTodos(for: priority)
                
                if !todos.isEmpty {
                    TodoListSection(todoList: todoList, priority: priority, todos: todos)
                    
                    if priority != .whenTime {
                        Divider()
                            .padding(.vertical, Theme.itemSpacing)
                    }
                }
            }
            
            // Completed section
            let completedTodos = todoList.todos.filter { $0.isCompleted }
            if !completedTodos.isEmpty {
                Divider()
                    .padding(.vertical, Theme.itemSpacing)
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
                .background(Color(NSColor.textBackgroundColor))
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
            .background(Color(NSColor.textBackgroundColor))
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
                            Text("#\(tag)")
                                .font(Theme.smallFont)
                                .foregroundColor(tag.lowercased() == "today" ? .white : Theme.text)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                        .fill(tag.lowercased() == "today" ? Theme.urgentTagColor : Theme.colorForTag(tag).opacity(0.25))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                        .stroke(tag.lowercased() == "today" ? Color.clear : Theme.colorForTag(tag).opacity(0.8), lineWidth: 1)
                                )
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
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(Theme.cornerRadius)
        .padding(.horizontal, Theme.contentPadding)
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