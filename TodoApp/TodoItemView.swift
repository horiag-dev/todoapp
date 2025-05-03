import SwiftUI

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
    @State var todo: Todo
    var isTop5: Bool = false
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
    
    init(todoList: TodoList, todo: Todo, isTop5: Bool = false) {
        self.todoList = todoList
        self._todo = State(initialValue: todo)
        self.isTop5 = isTop5
        _editedTitle = State(initialValue: todo.title)
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
    
    // Add this computed property to sort tags
    private var sortedTags: [String] {
        let todayTag = todo.tags.first { $0.lowercased() == "today" }
        let otherTags = todo.tags.filter { $0.lowercased() != "today" }.sorted()
        
        if let todayTag = todayTag {
            return [todayTag] + otherTags
        } else {
            return otherTags
        }
    }
    
    var body: some View {
        HStack(spacing: Theme.itemSpacing) {
            // Checkbox
            Button(action: {
                var updatedTodo = todo
                updatedTodo.isCompleted.toggle()
                if isTop5 {
                    todoList.toggleTop5Todo(updatedTodo)
                } else {
                    todoList.updateTodo(updatedTodo)
                }
                todo = updatedTodo
            }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? Theme.accent : Theme.secondaryText)
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
            
            // Content area
            if isEditing {
                TextField("Todo title", text: $editedTitle)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($focusField)
                    .onSubmit {
                        saveChanges()
                    }
                    .font(Theme.bodyFont)
                    .padding(6)
                    .background(Theme.background)
                    .cornerRadius(Theme.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .stroke(Theme.accent, lineWidth: 1)
                    )
            } else {
                // Todo text with links and tags
                HStack(spacing: Theme.itemSpacing) {
                    HStack(spacing: 0) {
                        ForEach(splitIntoSegments(text: todo.title)) { segment in
                            if segment.isLink {
                                Text(segment.text)
                                    .strikethrough(todo.isCompleted)
                                    .foregroundColor(Theme.accent)
                                    .underline()
                                    .font(Theme.bodyFont)
                                    .onTapGesture {
                                        if let url = segment.url {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                            } else {
                                Text(segment.text)
                                    .strikethrough(todo.isCompleted)
                                    .foregroundColor(todo.isCompleted ? Theme.secondaryText : Theme.text)
                                    .font(Theme.bodyFont)
                            }
                        }
                    }
                    
                    if !todo.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(sortedTags, id: \.self) { tag in
                                TagView(tag: tag)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Control buttons - always visible, right-aligned
            HStack(spacing: Theme.itemSpacing) {
                // Priority change buttons (only for non-top5, non-completed todos)
                if !isTop5 && !todo.isCompleted {
                    if todo.priority == .urgent {
                        Button(action: {
                            var updatedTodo = todo
                            updatedTodo.priority = .normal
                            todoList.updateTodo(updatedTodo)
                            todo = updatedTodo
                        }) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.secondaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Move to Normal priority")
                    } else if todo.priority == .normal {
                        Button(action: {
                            var updatedTodo = todo
                            updatedTodo.priority = .urgent
                            todoList.updateTodo(updatedTodo)
                            todo = updatedTodo
                        }) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.secondaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Move to Urgent priority")
                    }
                }
                // Tag management button
                Button(action: { showingTagManagement = true }) {
                    Image(systemName: "tag")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showingTagManagement, arrowEdge: .bottom) {
                    TagManagementPopover(
                        todo: todo,
                        todoList: todoList,
                        isPresented: $showingTagManagement,
                        isTop5: isTop5,
                        onTagChange: {
                            // Refresh local todo from model after tag change
                            if isTop5 {
                                if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                                    todo = updated
                                }
                            } else {
                                if let updated = todoList.todos.first(where: { $0.id == todo.id }) {
                                    todo = updated
                                }
                            }
                        }
                    )
                    .frame(width: 250, height: 300)
                }
                
                // Delete button
                Button(action: {
                    if isTop5 {
                        todoList.deleteTop5Todo(todo)
                    } else {
                        todoList.deleteTodo(todo)
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Theme.contentPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(
                    isEditing ? Theme.accent.opacity(0.1) :
                    (isSelected ? Theme.accent.opacity(0.08) : 
                    (isHovered ? Theme.secondaryBackground : Color.clear))
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
        .onChange(of: focusField) { oldValue, newValue in
            if !newValue && isEditing {
                saveChanges()
            }
        }
    }
    
    private func saveChanges() {
        if !editedTitle.isEmpty {
            var updatedTodo = todo
            updatedTodo.title = editedTitle
            if isTop5 {
                todoList.updateTop5Todo(updatedTodo)
            } else {
                todoList.updateTodo(updatedTodo)
            }
            todo = updatedTodo
        }
        isEditing = false
        focusField = false
    }
}

// New TagManagementPopover view
struct TagManagementPopover: View {
    let todo: Todo
    @ObservedObject var todoList: TodoList
    @Binding var isPresented: Bool
    var isTop5: Bool = false
    var onTagChange: (() -> Void)? = nil
    @State private var newTag = ""
    
    var availableTags: [String] {
        todoList.allTags.filter { !todo.tags.contains($0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Tags")
                    .font(Theme.headlineFont)
                Spacer()
            }
            .padding()
            .background(Theme.secondaryBackground)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    // New tag input
                    HStack {
                        TextField("Add new tag", text: $newTag)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(Theme.bodyFont)
                        
                        Button(action: addNewTag) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Theme.accent)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(newTag.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Current tags
                    if !todo.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Tags")
                                .font(Theme.smallFont)
                                .foregroundColor(Theme.secondaryText)
                            
                            ForEach(todo.tags, id: \.self) { tag in
                                TagRowView(tag: tag, isCurrentTag: true)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Available tags
                    if !availableTags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available Tags")
                                .font(Theme.smallFont)
                                .foregroundColor(Theme.secondaryText)
                            
                            ForEach(availableTags, id: \.self) { tag in
                                TagRowView(tag: tag, isCurrentTag: false)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(Theme.background)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private func addNewTag() {
        if !newTag.isEmpty {
            if isTop5 {
                todoList.addTagToTop5Todo(todo, tag: newTag)
            } else {
                todoList.addTag(to: todo, tag: newTag)
            }
            newTag = ""
            onTagChange?()
        }
    }
    
    private func addTag(_ tag: String) {
        if isTop5 {
            todoList.addTagToTop5Todo(todo, tag: tag)
        } else {
            todoList.addTag(to: todo, tag: tag)
        }
        onTagChange?()
    }
    
    private func removeTag(_ tag: String) {
        if isTop5 {
            todoList.removeTagFromTop5Todo(todo, tag: tag)
        } else {
            todoList.removeTag(from: todo, tag: tag)
        }
        onTagChange?()
    }
    
    private func TagRowView(tag: String, isCurrentTag: Bool) -> some View {
        let tagColor = Theme.colorForTag(tag)
        
        return HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(tagColor)
                    .frame(width: 8, height: 8)
                Text(tag)
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.text)
            }
            Spacer()
            Button(action: { 
                if isCurrentTag {
                    removeTag(tag)
                } else {
                    addTag(tag)
                }
            }) {
                Image(systemName: isCurrentTag ? "xmark" : "plus")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.secondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(tagColor.opacity(0.5), lineWidth: 1)
                )
        )
    }
} 
