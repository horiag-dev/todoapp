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
    @State private var newTodoPriority: Priority = .urgent
    @State private var showingTagManagement = false
    @State private var selectedTags: Set<String> = []
    @State private var leftColumnWidth: CGFloat = 300
    @State private var middleColumnWidth: CGFloat = 300
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            Theme.mainBackgroundGradient
                .ignoresSafeArea()
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
                    
                    // Settings button for LLM configuration
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                    .popover(isPresented: $showingSettings) {
                        SettingsView(llmService: todoList.llmService)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                
                // Main Content with Resizable Columns
                HStack(spacing: 0) {
                    // Left Column - Goals
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
                                    MarkdownEditor(text: todoList.goals, todoList: todoList)
                                        .padding(.horizontal, Theme.contentPadding)
                                }
                                .frame(height: geometry.size.height)
                            }
                        }
                    }
                    .frame(width: leftColumnWidth)
                    
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
                        
                        TagListView(todoList: todoList, selectedTag: $selectedTag)
                    }
                    .frame(width: middleColumnWidth)
                    
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
                            .scrollIndicators(.hidden) // Hide scroll indicators for cleaner look
                            .clipped() // Ensure content is clipped for better performance
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(Theme.cornerRadius)
                            .padding(.horizontal, Theme.contentPadding)
                        }
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
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
            newTodoPriority = .urgent
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

// Reusable tag pill view for consistent tag styling
struct TagPillView: View {
    let tag: String
    let isSelected: Bool
    var body: some View {
        Text("#\(tag)")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(tag.lowercased() == "today" ? .white : (isSelected ? .blue : Theme.text))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tag.lowercased() == "today" ? Theme.urgentTagColor : (isSelected ? Color.blue.opacity(0.2) : Theme.colorForTag(tag).opacity(0.25)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(tag.lowercased() == "today" ? Color.clear : Theme.colorForTag(tag).opacity(0.8), lineWidth: 1)
            )
    }
}

struct NewTodoInput: View {
    @ObservedObject var todoList: TodoList
    @Binding var newTodoTitle: String
    @Binding var newTodoPriority: Priority
    @Binding var showingTagManagement: Bool
    @Binding var selectedTags: Set<String>
    @FocusState private var isTextFieldFocused: Bool
    
    // AI Refactoring states
    @State private var showingAISuggestions = false
    @State private var aiSuggestions: (title: String, tags: [String], priority: Priority)?
    @State private var isRefactoring = false
    
    // Get all unique tags from the todo list
    private var availableTags: [String] {
        todoList.allTags.sorted()
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Inline selected tags
                ForEach(Array(selectedTags), id: \.self) { tag in
                    HStack(spacing: 4) {
                        TagPillView(tag: tag, isSelected: true)
                        Button(action: { selectedTags.remove(tag) }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .imageScale(.small)
                        }
                    }
                }
                
                TextField("New todo", text: $newTodoTitle)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isTextFieldFocused ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isTextFieldFocused ? 2 : 1)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.windowBackgroundColor))
                            )
                    )
                    .focused($isTextFieldFocused)
                    .onSubmit(createTodo)
                
                // AI Refactor button
                Button(action: refactorWithAI) {
                    Image(systemName: isRefactoring ? "wand.and.stars.inverse" : "wand.and.stars")
                        .foregroundColor(.purple)
                        .imageScale(.medium)
                        .rotationEffect(.degrees(isRefactoring ? 360 : 0))
                        .animation(isRefactoring ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefactoring)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(newTodoTitle.isEmpty || isRefactoring)
                .help("Refactor with AI")
                
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
            
            // AI Suggestions Preview
            if let suggestions = aiSuggestions, showingAISuggestions {
                VStack(spacing: 8) {
                    HStack {
                        Text("AI Suggestions:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                        
                        Spacer()
                        
                        Button("Apply") {
                            applyAISuggestions(suggestions)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button("Dismiss") {
                            showingAISuggestions = false
                            aiSuggestions = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title: \(suggestions.title)")
                            .font(.caption)
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("Tags:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(suggestions.tags, id: \.self) { tag in
                                TagPillView(tag: tag, isSelected: false)
                            }
                        }
                        
                        HStack {
                            Text("Priority:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Image(systemName: suggestions.priority.icon)
                                .foregroundColor(suggestions.priority.color)
                                .imageScale(.small)
                            
                            Text(suggestions.priority.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 12)
            }
            
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
                                TagPillView(tag: tag, isSelected: selectedTags.contains(tag))
                            }
                            .buttonStyle(PlainButtonStyle())
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
    
    private func refactorWithAI() {
        guard !newTodoTitle.isEmpty else { return }
        
        isRefactoring = true
        
        Task {
            let suggestions = await todoList.refactorTodoWithAI(newTodoTitle)
            
            await MainActor.run {
                isRefactoring = false
                
                if let suggestions = suggestions {
                    aiSuggestions = suggestions
                    showingAISuggestions = true
                } else {
                    // Show error if available
                    if let error = todoList.llmService.lastError {
                        // You could show an alert here
                        print("AI Refactoring error: \(error)")
                    }
                }
            }
        }
    }
    
    private func applyAISuggestions(_ suggestions: (title: String, tags: [String], priority: Priority)) {
        newTodoTitle = suggestions.title
        selectedTags = Set(suggestions.tags)
        newTodoPriority = suggestions.priority
        showingAISuggestions = false
        aiSuggestions = nil
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
            newTodoPriority = .urgent
            showingAISuggestions = false
            aiSuggestions = nil
        }
    }
}

struct TodoListSections: View {
    @ObservedObject var todoList: TodoList
    
    // Cache for filtered and sorted todos to improve performance
    @State private var cachedFilteredTodos: [Priority: [Todo]] = [:]
    @State private var lastTodoListHash: Int = 0
    
    private func filterAndSortTodos(for priority: Priority) -> [Todo] {
        // Create a simple hash of the todo list to detect changes
        let currentHash = todoList.todos.map { "\($0.id)\($0.isCompleted)\($0.priority.rawValue)\($0.tags.joined())" }.joined().hashValue
        
        // Return cached result if nothing has changed
        if currentHash == lastTodoListHash, let cached = cachedFilteredTodos[priority] {
            return cached
        }
        
        // Update cache if needed
        if currentHash != lastTodoListHash {
            cachedFilteredTodos.removeAll()
            lastTodoListHash = currentHash
        }
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
        
        // Separate todos into tagged and untagged groups
        let untaggedTodos = filteredTodos.filter { todo in
            // Consider a todo untagged if it has no tags or only has the "today" tag
            todo.tags.isEmpty || todo.tags.allSatisfy { $0.lowercased() == "today" }
        }
        
        let taggedTodos = filteredTodos.filter { todo in
            // Consider a todo tagged if it has at least one non-"today" tag
            todo.tags.contains { $0.lowercased() != "today" }
        }
        
        // Group tagged todos by their first non-"today" tag
        let groupedTodos = Dictionary(grouping: taggedTodos) { todo -> String in
            // Get the first non-"today" tag
            todo.tags.first { $0.lowercased() != "today" }!
        }
        
        // First, get sorted tagged todos
        let sortedTaggedTodos = groupedTodos.sorted { $0.key < $1.key }
            .flatMap { _, todos in
                // Within each tag group, sort todos alphabetically by title
                todos.sorted { $0.title.lowercased() < $1.title.lowercased() }
            }
        
        // Then append untagged todos, sorted alphabetically
        let sortedUntaggedTodos = untaggedTodos.sorted { $0.title.lowercased() < $1.title.lowercased() }
        
        // Combine the results with untagged todos at the end
        let result = sortedTaggedTodos + sortedUntaggedTodos
        
        // Cache the result
        cachedFilteredTodos[priority] = result
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top 5 of the week section
            if !todoList.top5Todos.isEmpty {
                TodoListSection(todoList: todoList, priority: nil, todos: todoList.top5Todos, customTitle: "🗓️ Top 5 of the week")
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 6)
                    .padding(.vertical, Theme.itemSpacing * 2)
            }
            ForEach([Priority.urgent, Priority.normal, Priority.whenTime], id: \.self) { priority in
                let todos = filterAndSortTodos(for: priority)
                if !todos.isEmpty {
                    TodoListSection(todoList: todoList, priority: priority, todos: todos, customTitle: nil)
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
                TodoListSection(todoList: todoList, priority: nil, todos: completedTodos, customTitle: nil)
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
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, Theme.contentPadding)
                        }
                    },
                    label: {
                        HStack {
                            Text("Deleted Items")
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
        .drawingGroup() // Optimize rendering performance for smooth scrolling
    }
}

struct TodoListSection: View {
    let todoList: TodoList
    let priority: Priority?
    let todos: [Todo]
    let customTitle: String?
    
    var title: String {
        if let customTitle = customTitle {
            return customTitle
        }
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
                    if priority == nil && customTitle == nil { // This is the completed section
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
                LazyVStack(spacing: 0) {
                    ForEach(todos) { todo in
                        TodoItemView(todoList: todoList, todo: todo, isTop5: customTitle == "🗓️ Top 5 of the week")
                    }
                }
            }
            .padding(.vertical, 2)
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