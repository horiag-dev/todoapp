import SwiftUI

struct PriorityMenuView: View {
    let todo: Todo
    @ObservedObject var todoList: TodoList
    
    var body: some View {
        Menu {
            ForEach(Priority.allCases, id: \.self) { priority in
                Button(action: {
                    var updatedTodo = todo
                    updatedTodo.priority = priority
                    todoList.updateTodo(updatedTodo)
                }) {
                    HStack {
                        Image(systemName: priority.icon)
                            .foregroundColor(priority.color)
                        Text(priority.rawValue)
                        if todo.priority == priority {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: todo.priority.icon)
                .foregroundColor(todo.priority.color)
        }
    }
}

struct TagManagementSheet: View {
    let todo: Todo
    @ObservedObject var todoList: TodoList
    @Binding var isPresented: Bool
    @State private var newTag = ""
    
    var availableTags: [String] {
        todoList.allTags.filter { !todo.tags.contains($0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Tags")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            // Content
            List {
                // Current tags section
                if !todo.tags.isEmpty {
                    Section("Current Tags") {
                        ForEach(todo.tags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button(action: {
                                    todoList.removeTag(from: todo, tag: tag)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                
                // Available tags section
                if !availableTags.isEmpty {
                    Section("Add Existing Tags") {
                        ForEach(availableTags, id: \.self) { tag in
                            Button(action: {
                                todoList.addTag(to: todo, tag: tag)
                            }) {
                                HStack {
                                    Text(tag)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                // New tag section
                Section("Create New Tag") {
                    HStack {
                        TextField("Type tag name", text: $newTag)
                            .textFieldStyle(PlainTextFieldStyle())
                        Button(action: {
                            if !newTag.isEmpty {
                                todoList.addTag(to: todo, tag: newTag)
                                newTag = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
    }
}

struct TodoItemView: View {
    @ObservedObject var todoList: TodoList
    let todo: Todo
    @State private var isHovered = false
    @State private var isSelected = false
    @State private var isEditing = false
    @State private var editedTitle: String
    @State private var showingTagManagement = false
    @FocusState private var focusField: Bool
    
    // Helper struct to represent text segments
    private struct TextSegment: Identifiable {
        let id = UUID()
        let text: String
        let isLink: Bool
        let url: URL?
    }
    
    // Function to split text into segments
    private func splitIntoSegments(text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsString = text as NSString
        var currentIndex = 0
        
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []
        
        for match in matches {
            // Add text before link if any
            if match.range.location > currentIndex {
                let normalText = nsString.substring(with: NSRange(location: currentIndex, length: match.range.location - currentIndex))
                segments.append(TextSegment(text: normalText, isLink: false, url: nil))
            }
            
            // Add link
            let linkText = nsString.substring(with: match.range)
            segments.append(TextSegment(text: linkText, isLink: true, url: match.url))
            
            currentIndex = match.range.location + match.range.length
        }
        
        // Add remaining text if any
        if currentIndex < nsString.length {
            let normalText = nsString.substring(with: NSRange(location: currentIndex, length: nsString.length - currentIndex))
            segments.append(TextSegment(text: normalText, isLink: false, url: nil))
        }
        
        return segments
    }
    
    init(todoList: TodoList, todo: Todo) {
        self.todoList = todoList
        self.todo = todo
        _editedTitle = State(initialValue: todo.title)
    }
    
    // Function to generate a consistent color for a tag
    private func colorForTag(_ tag: String) -> Color {
        // Reserve red for urgent and today tags
        if tag == "urgent" || tag == "today" {
            return .red
        }
        
        // Generate a consistent color based on the tag string
        let colors: [Color] = [
            .blue,
            .green,
            .orange,
            .purple,
            .teal,
            .indigo,
            .mint,
            .pink,
            .cyan,
            .brown
        ]
        
        // Use the hash of the tag string to pick a consistent color
        var hash = 0
        for char in tag {
            hash = ((hash << 5) &+ hash) &+ Int(char.asciiValue ?? 0)
        }
        return colors[abs(hash) % colors.count]
    }
    
    var body: some View {
        HStack {
            Button(action: {
                var updatedTodo = todo
                updatedTodo.isCompleted.toggle()
                todoList.updateTodo(updatedTodo)
            }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? .green : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isEditing {
                TextField("Todo title", text: $editedTitle)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($focusField)
                    .onSubmit {
                        saveChanges()
                    }
                    .padding(6)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue, lineWidth: 1)
                    )
            } else {
                HStack(spacing: 0) {
                    ForEach(splitIntoSegments(text: todo.title)) { segment in
                        if segment.isLink {
                            Text(segment.text)
                                .strikethrough(todo.isCompleted)
                                .foregroundColor(.blue)
                                .underline()
                                .onTapGesture {
                                    if let url = segment.url {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                        } else {
                            Text(segment.text)
                                .strikethrough(todo.isCompleted)
                                .foregroundColor(todo.isCompleted ? .secondary : .primary)
                        }
                    }
                }
            }
            
            if !todo.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(todo.tags), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 12))
                            .foregroundColor(colorForTag(tag))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(colorForTag(tag).opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: {
                    var updatedTodo = todo
                    switch todo.priority {
                    case .whenTime:
                        updatedTodo.priority = .normal
                    case .normal:
                        updatedTodo.priority = .urgent
                    case .urgent:
                        break
                    }
                    todoList.updateTodo(updatedTodo)
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(todo.priority == .urgent ? .gray : .blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(todo.priority == .urgent)
                
                Button(action: {
                    var updatedTodo = todo
                    switch todo.priority {
                    case .urgent:
                        updatedTodo.priority = .normal
                    case .normal:
                        updatedTodo.priority = .whenTime
                    case .whenTime:
                        break
                    }
                    todoList.updateTodo(updatedTodo)
                }) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(todo.priority == .whenTime ? .gray : .blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(todo.priority == .whenTime)
                
                Button(action: { isEditing = true }) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { showingTagManagement = true }) {
                    Image(systemName: "tag.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .sheet(isPresented: $showingTagManagement) {
                    TagManagementSheet(todo: todo, todoList: todoList, isPresented: $showingTagManagement)
                }
                
                Button(action: {
                    todoList.deleteTodo(todo)
                }) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isEditing ? Color.blue.opacity(0.1) :
                    (isSelected ? Color.blue.opacity(0.15) : 
                    (isHovered ? Color.gray.opacity(0.08) : Color.clear))
                )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .gesture(
            TapGesture(count: 2).onEnded {
                isEditing = true
                editedTitle = todo.title
                focusField = true
            }
        )
        .onChange(of: focusField) { focused in
            if !focused && isEditing {
                saveChanges()
            }
        }
    }
    
    private func saveChanges() {
        if !editedTitle.isEmpty {
            var updatedTodo = todo
            updatedTodo.title = editedTitle
            todoList.updateTodo(updatedTodo)
        }
        isEditing = false
        focusField = false
    }
} 
