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
    @State private var showingNewTagAlert = false
    @State private var newTagText = ""
    @FocusState private var focusField: Bool

    // Static cached NSDataDetector for link detection (expensive to create)
    private static let linkDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()
    
    // Function to get the primary tag color for background
    private var primaryTagColor: Color? {
        guard todo.priority == .urgent, let firstTag = todo.tags.first else { return nil }
        // Use the first tag as the primary tag for background color
        return Theme.colorForTag(firstTag)
    }
    
    
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
        let nsString = text as NSString
        var currentIndex = 0

        let matches = Self.linkDetector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []
        
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
                                TagPillView(tag: tag, size: .small)
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Theme.contentPadding)
        .background(
            isEditing ? Theme.accent.opacity(0.1) :
            (isSelected ? Theme.accent.opacity(0.08) :
            (isHovered ? Theme.secondaryBackground :
            (primaryTagColor?.opacity(0.12) ?? Color.clear)))
        )
        .animation(Theme.Animation.microSpring, value: isHovered)
        .animation(Theme.Animation.microSpring, value: isSelected)
        .animation(Theme.Animation.microSpring, value: isEditing)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            // Priority actions
            if !isTop5 && !todo.isCompleted {
                Menu("Priority") {
                    Button {
                        var updatedTodo = todo
                        updatedTodo.priority = .urgent
                        todoList.updateTodo(updatedTodo)
                        todo = updatedTodo
                    } label: {
                        Label("Urgent", systemImage: "flag.fill")
                    }
                    .disabled(todo.priority == .urgent)

                    Button {
                        var updatedTodo = todo
                        updatedTodo.priority = .normal
                        todoList.updateTodo(updatedTodo)
                        todo = updatedTodo
                    } label: {
                        Label("Normal", systemImage: "flag")
                    }
                    .disabled(todo.priority == .normal)

                    Button {
                        var updatedTodo = todo
                        updatedTodo.priority = .whenTime
                        todoList.updateTodo(updatedTodo)
                        todo = updatedTodo
                    } label: {
                        Label("When there's time", systemImage: "clock")
                    }
                    .disabled(todo.priority == .whenTime)
                }
            }

            // Tags submenu
            Menu("Tags") {
                // Current tags (to remove)
                if !todo.tags.isEmpty {
                    ForEach(todo.tags, id: \.self) { tag in
                        Button {
                            if isTop5 {
                                todoList.removeTagFromTop5Todo(todo, tag: tag)
                            } else {
                                todoList.removeTag(from: todo, tag: tag)
                            }
                            // Refresh
                            if isTop5 {
                                if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                                    self.todo = updated
                                }
                            } else {
                                if let updated = todoList.todos.first(where: { $0.id == todo.id }) {
                                    self.todo = updated
                                }
                            }
                        } label: {
                            Label("Remove #\(tag)", systemImage: "minus.circle")
                        }
                    }
                    Divider()
                }

                // Available tags (to add)
                let availableTags = todoList.allTags.filter { !todo.tags.contains($0) }
                if !availableTags.isEmpty {
                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            if isTop5 {
                                todoList.addTagToTop5Todo(todo, tag: tag)
                            } else {
                                todoList.addTag(to: todo, tag: tag)
                            }
                            // Refresh
                            if isTop5 {
                                if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                                    self.todo = updated
                                }
                            } else {
                                if let updated = todoList.todos.first(where: { $0.id == todo.id }) {
                                    self.todo = updated
                                }
                            }
                        } label: {
                            Label("Add #\(tag)", systemImage: "plus.circle")
                        }
                    }
                }

                Divider()

                Button {
                    showingNewTagAlert = true
                } label: {
                    Label("New Tag...", systemImage: "plus")
                }
            }

            Divider()

            // Edit
            Button {
                isEditing = true
                editedTitle = todo.title
                focusField = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            // Complete/Uncomplete
            Button {
                var updatedTodo = todo
                updatedTodo.isCompleted.toggle()
                if isTop5 {
                    todoList.toggleTop5Todo(updatedTodo)
                } else {
                    todoList.updateTodo(updatedTodo)
                }
                todo = updatedTodo
            } label: {
                Label(todo.isCompleted ? "Mark Incomplete" : "Mark Complete", systemImage: todo.isCompleted ? "circle" : "checkmark.circle")
            }

            Divider()

            // Delete
            Button(role: .destructive) {
                if isTop5 {
                    todoList.deleteTop5Todo(todo)
                } else {
                    todoList.deleteTodo(todo)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("New Tag", isPresented: $showingNewTagAlert) {
            TextField("Tag name", text: $newTagText)
            Button("Cancel", role: .cancel) {
                newTagText = ""
            }
            Button("Add") {
                addNewTag()
            }
        } message: {
            Text("Enter a name for the new tag")
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
        .id("\(todo.id)-\(todo.isCompleted)-\(todo.priority.rawValue)")
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

    private func addNewTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }

        if isTop5 {
            todoList.addTagToTop5Todo(todo, tag: tag)
            if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                todo = updated
            }
        } else {
            todoList.addTag(to: todo, tag: tag)
            if let updated = todoList.todos.first(where: { $0.id == todo.id }) {
                todo = updated
            }
        }

        newTagText = ""
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
        if isCurrentTag {
            return AnyView(
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(tagColor)
                            .frame(width: 8, height: 8)
                        Text(tag)
                            .font(Theme.bodyFont)
                            .foregroundColor(Theme.text)
                    }
                    Spacer()
                    Button(action: { removeTag(tag) }) {
                        Image(systemName: "xmark")
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
            )
        } else {
            return AnyView(
                Button(action: { addTag(tag) }) {
                    HStack {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(tagColor)
                                .frame(width: 8, height: 8)
                            Text(tag)
                                .font(Theme.bodyFont)
                                .foregroundColor(Theme.text)
                        }
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.secondaryText)
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
                .buttonStyle(PlainButtonStyle())
            )
        }
    }
} 
