import SwiftUI
import AppKit

// Section with header and content items
struct GoalSection: Identifiable {
    let id = UUID()
    var title: String
    var items: [String]  // Sub-bullets or content lines

    var accentColor: Color {
        let colors: [Color] = [
            .blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint
        ]
        var hash = 0
        for char in title.unicodeScalars {
            hash = hash &+ Int(char.value)
        }
        return colors[abs(hash) % colors.count]
    }
}

// Visual Goals view with sections
struct EditableGoalsView: View {
    @ObservedObject var todoList: TodoList
    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    // Parse markdown into sections (headers with their content)
    private var sections: [GoalSection] {
        let lines = todoList.goals.components(separatedBy: .newlines)
        var result: [GoalSection] = []
        var currentSection: GoalSection? = nil
        var standaloneItems: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                continue
            }

            // Check for bold headers: **text** or **text** #tag
            if trimmed.hasPrefix("**"), let endRange = trimmed.range(of: "**", range: trimmed.index(trimmed.startIndex, offsetBy: 2)..<trimmed.endIndex) {
                // Save previous section
                if let section = currentSection {
                    result.append(section)
                }
                // Save standalone items as "General" section
                if !standaloneItems.isEmpty && currentSection == nil {
                    result.append(GoalSection(title: "General", items: standaloneItems))
                    standaloneItems = []
                }

                // Extract header text (between ** and **)
                let startIdx = trimmed.index(trimmed.startIndex, offsetBy: 2)
                let headerText = String(trimmed[startIdx..<endRange.lowerBound])

                currentSection = GoalSection(title: headerText, items: [])
            }
            // Also support # headers
            else if trimmed.hasPrefix("#") {
                if let section = currentSection {
                    result.append(section)
                }
                if !standaloneItems.isEmpty && currentSection == nil {
                    result.append(GoalSection(title: "General", items: standaloneItems))
                    standaloneItems = []
                }

                var headerText = trimmed
                while headerText.hasPrefix("#") {
                    headerText = String(headerText.dropFirst())
                }
                headerText = headerText.trimmingCharacters(in: .whitespaces)

                currentSection = GoalSection(title: headerText, items: [])
            } else {
                // Content line - clean up prefixes
                var content = trimmed

                // Remove list markers
                if content.hasPrefix("- ") || content.hasPrefix("* ") {
                    content = String(content.dropFirst(2))
                } else if let match = content.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    content = String(content[match.upperBound...])
                }

                content = content.trimmingCharacters(in: .whitespaces)

                if !content.isEmpty {
                    if currentSection != nil {
                        currentSection?.items.append(content)
                    } else {
                        standaloneItems.append(content)
                    }
                }
            }
        }

        // Don't forget the last section
        if let section = currentSection {
            result.append(section)
        }

        // Add standalone items if any remain
        if !standaloneItems.isEmpty {
            result.insert(GoalSection(title: "Focus", items: standaloneItems), at: 0)
        }

        return result
    }

    var body: some View {
        ZStack {
            if isEditing {
                // Edit mode - TextEditor for markdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit Goals")
                        .font(Theme.smallFont)
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 4)

                    TextEditor(text: $editText)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(Theme.cornerRadius)
                        .focused($isFocused)
                        .onAppear {
                            editText = todoList.goals
                            isFocused = true
                        }

                    Text("Use # for headers, - for bullets")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText.opacity(0.7))
                        .padding(.horizontal, 4)
                }
            } else {
                // View mode - Visual sections
                ScrollView {
                    if sections.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 32))
                                .foregroundColor(Theme.secondaryText.opacity(0.5))
                            Text("No goals yet")
                                .font(Theme.bodyFont)
                                .foregroundColor(Theme.secondaryText)
                            Text("Click edit to add your goals")
                                .font(Theme.smallFont)
                                .foregroundColor(Theme.secondaryText.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(sections) { section in
                                GoalSectionCard(section: section)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .overlay(
            // Edit/Done button
            Button(action: {
                if isEditing {
                    saveAndExitEdit()
                } else {
                    editText = todoList.goals
                    withAnimation(Theme.Animation.quickFade) {
                        isEditing = true
                    }
                }
            }) {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isEditing ? .white : Theme.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isEditing ? Color.green : Theme.secondaryBackground)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help(isEditing ? "Save" : "Edit goals")
            .padding(8),
            alignment: .topTrailing
        )
        .animation(Theme.Animation.quickFade, value: isEditing)
    }

    private func saveAndExitEdit() {
        todoList.goals = editText
        todoList.saveTodos()
        withAnimation(Theme.Animation.quickFade) {
            isEditing = false
        }
    }
}

// Visual section card with header and bullet items
struct GoalSectionCard: View {
    let section: GoalSection
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(section.accentColor)
                    .frame(width: 4, height: 18)

                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
            }

            // Bullet items
            if !section.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(section.accentColor.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)

                            Text(item)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.text.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .fill(Color(NSColor.textBackgroundColor))
                .shadow(
                    color: isHovered ? Theme.Shadow.hoverColor : Theme.Shadow.cardColor,
                    radius: isHovered ? Theme.Shadow.hoverRadius : Theme.Shadow.cardRadius,
                    y: isHovered ? Theme.Shadow.hoverY : Theme.Shadow.cardY
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .stroke(section.accentColor.opacity(isHovered ? 0.25 : 0.1), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(Theme.Animation.microSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// Markdown renderer (read-only display)
struct MarkdownRenderer: View {
    let text: String

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
                                Text((try? AttributedString(markdown: item.content)) ?? AttributedString(item.content))
                                if !item.tags.isEmpty {
                                    ForEach(item.tags, id: \.self) { tag in
                                        TagPillView(tag: tag, size: .small)
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
                                Text((try? AttributedString(markdown: item.content)) ?? AttributedString(item.content))
                                if !item.tags.isEmpty {
                                    ForEach(item.tags, id: \.self) { tag in
                                        TagPillView(tag: tag, size: .small)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    HStack {
                        Text((try? AttributedString(markdown: item.content)) ?? AttributedString(item.content))
                        if !item.tags.isEmpty {
                            ForEach(item.tags, id: \.self) { tag in
                                TagPillView(tag: tag, size: .small)
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
    @State private var leftColumnWidth: CGFloat = 380
    @State private var middleColumnWidth: CGFloat = 280
    @State private var isTagsColumnVisible: Bool = false  // Hidden by default
    @State private var isInMindMapMode: Bool = false  // Toggle between list and mind map views
    
    var body: some View {
        ZStack {
            Theme.mainBackgroundGradient
                .ignoresSafeArea()
            VStack(spacing: 0) {
                // Top Bar - File Management
                HStack(spacing: 12) {
                    Button(action: { todoList.openFile() }) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .help("Open existing todo file")

                    Button(action: { todoList.createNewFile() }) {
                        Image(systemName: "doc.badge.plus")
                    }
                    .help("Create new todo file")

                    Spacer()

                    // Mind map toggle button
                    Button(action: {
                        withAnimation(Theme.Animation.panelSlide) {
                            isInMindMapMode.toggle()
                        }
                    }) {
                        Image(systemName: isInMindMapMode ? "list.bullet" : "circle.grid.cross")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isInMindMapMode ? Theme.accent : Theme.secondaryText)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .fill(isInMindMapMode ? Theme.accent.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(isInMindMapMode ? "Switch to List View" : "Switch to Mind Map View")

                    // Tags column toggle button (only visible in list mode)
                    if !isInMindMapMode {
                        Button(action: {
                            withAnimation(Theme.Animation.panelSlide) {
                                isTagsColumnVisible.toggle()
                            }
                        }) {
                            Image(systemName: "tag")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(isTagsColumnVisible ? Theme.accent : Theme.secondaryText)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                        .fill(isTagsColumnVisible ? Theme.accent.opacity(0.15) : Color.clear)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(isTagsColumnVisible ? "Hide Tags" : "Show Tags")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                // Main Content - Either Mind Map or List View
                if isInMindMapMode {
                    // Mind Map View
                    MindMapView(todoList: todoList)
                        .transition(.opacity)
                } else {
                    // List View with Resizable Columns
                    HStack(spacing: 0) {
                        // Left Column - Goals & Quotes
                        VStack(spacing: 0) {
                            Text("Goals")
                                .font(Theme.titleFont)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.contentPadding)
                                .padding(.top, Theme.contentPadding)
                                .padding(.bottom, 8)

                            // Quotes section (compact, at top)
                            QuotesSection(todoList: todoList)
                                .padding(.horizontal, Theme.contentPadding)
                                .padding(.bottom, 12)

                            // Goals section (scrollable)
                            EditableGoalsView(todoList: todoList)
                                .padding(.horizontal, Theme.contentPadding)
                        }
                        .frame(width: leftColumnWidth)

                        // Resizable divider for Goals
                        ResizableBar(width: $leftColumnWidth, minWidth: 200, maxWidth: 500)

                        // Middle Column - Tags (Collapsible)
                        if isTagsColumnVisible {
                            VStack(spacing: Theme.itemSpacing) {
                                HStack {
                                    Text("Tags")
                                        .font(Theme.titleFont)
                                    Spacer()
                                    Button(action: {
                                        withAnimation(Theme.Animation.panelSlide) {
                                            isTagsColumnVisible = false
                                        }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(Theme.secondaryText)
                                            .frame(width: 20, height: 20)
                                            .background(
                                                Circle()
                                                    .fill(Theme.secondaryText.opacity(0.1))
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.horizontal, Theme.contentPadding)
                                .padding(.vertical, Theme.contentPadding)

                                TagListView(todoList: todoList, selectedTag: $selectedTag)
                            }
                            .frame(width: middleColumnWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))

                            // Resizable divider for Tags
                            ResizableBar(width: $middleColumnWidth, minWidth: 200, maxWidth: 400)
                        }

                        // Right Column - Todos
                        VStack(spacing: 0) {
                            Text("Todos")
                                .font(Theme.titleFont)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.contentPadding)
                                .padding(.vertical, Theme.contentPadding)

                            // New Todo Input
                            NewTodoInput(
                                todoList: todoList,
                                newTodoTitle: $newTodoTitle,
                                newTodoPriority: $newTodoPriority
                            )

                            // Sticky Top 5 Section (outside ScrollView)
                            if !todoList.top5Todos.isEmpty {
                                Top5WeekSection(todoList: todoList)
                                    .padding(.top, 8)
                            }

                            // Scrollable todo list (without Top 5)
                            ScrollView {
                                TodoListSections(todoList: todoList, excludeTop5: true)
                            }
                            .scrollIndicators(.hidden)
                            .clipped()
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(Theme.cornerRadius)
                            .padding(.horizontal, Theme.contentPadding)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
    }
    
    private func createTodo() {
        if !newTodoTitle.isEmpty {
            // Parse hashtags from title
            let (cleanTitle, parsedTags) = parseHashtags(from: newTodoTitle)

            let todo = Todo(
                title: cleanTitle,
                isCompleted: false,
                tags: parsedTags,
                priority: newTodoPriority
            )
            todoList.addTodo(todo)
            newTodoTitle = ""
            newTodoPriority = .urgent
        }
    }

    private func parseHashtags(from text: String) -> (cleanTitle: String, tags: [String]) {
        let words = text.components(separatedBy: " ")
        var cleanWords: [String] = []
        var tags: [String] = []

        for word in words {
            if word.hasPrefix("#") && word.count > 1 {
                let tag = String(word.dropFirst())
                tags.append(tag)
            } else {
                cleanWords.append(word)
            }
        }

        return (cleanWords.joined(separator: " "), tags)
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

// Unified tag pill view for consistent tag styling across the app
struct TagPillView: View {
    let tag: String
    var isSelected: Bool = false
    var size: TagPillSize = .regular
    var interactive: Bool = true  // Enable hover effects

    @State private var isHovered: Bool = false

    enum TagPillSize {
        case small   // For inline display in todo items
        case regular // For tag selection, lists
    }

    private var isSpecialTag: Bool {
        let lowercased = tag.lowercased()
        return lowercased == "urgent" || lowercased == "today"
    }

    private var tagColor: Color {
        Theme.colorForTag(tag)
    }

    private var fontSize: Font {
        switch size {
        case .small: return Theme.smallFont
        case .regular: return .system(size: 11, weight: .medium)
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return 6
        case .regular: return 8
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .small: return 3
        case .regular: return 4
        }
    }

    var body: some View {
        Text("#\(tag)")
            .font(fontSize)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(backgroundColor)
                    .shadow(
                        color: isHovered && interactive ? Theme.Shadow.cardColor : Color.clear,
                        radius: isHovered ? Theme.Shadow.cardRadius : 0,
                        y: isHovered ? Theme.Shadow.cardY : 0
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isHovered && interactive ? 1.05 : 1.0)
            .animation(Theme.Animation.microSpring, value: isHovered)
            .animation(Theme.Animation.microSpring, value: isSelected)
            .onHover { hovering in
                if interactive {
                    isHovered = hovering
                }
            }
    }

    private var foregroundColor: Color {
        if isSpecialTag {
            return .white
        } else if isSelected {
            return .blue
        } else {
            return Theme.text
        }
    }

    private var backgroundColor: Color {
        if isSpecialTag {
            return tagColor
        } else if isSelected {
            return Color.blue.opacity(0.2)
        } else {
            return tagColor.opacity(0.25)
        }
    }

    private var borderColor: Color {
        if isSpecialTag {
            return Color.clear
        } else {
            return tagColor.opacity(0.8)
        }
    }
}

struct NewTodoInput: View {
    @ObservedObject var todoList: TodoList
    @Binding var newTodoTitle: String
    @Binding var newTodoPriority: Priority
    @FocusState private var isTextFieldFocused: Bool
    @State private var selectedTags: Set<String> = []

    private var availableTags: [String] {
        todoList.allTags.sorted()
    }

    var body: some View {
        VStack(spacing: 6) {
            // Main input row
            HStack(spacing: 10) {
                // Priority indicator
                Image(systemName: newTodoPriority == .urgent ? "flag.fill" : (newTodoPriority == .normal ? "flag" : "clock.fill"))
                    .font(.system(size: 14))
                    .foregroundColor(newTodoPriority == .urgent ? .red : (newTodoPriority == .normal ? Theme.accent : Theme.secondaryText))
                    .onTapGesture {
                        withAnimation(Theme.Animation.microSpring) {
                            switch newTodoPriority {
                            case .urgent: newTodoPriority = .normal
                            case .normal: newTodoPriority = .whenTime
                            case .whenTime: newTodoPriority = .urgent
                            }
                        }
                    }

                TextField("Add a new todo...", text: $newTodoTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isTextFieldFocused)
                    .onSubmit(createTodo)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(Theme.cornerRadiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                    .stroke(isTextFieldFocused ? Theme.accent.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, Theme.contentPadding)

            // Quick tag buttons
            if !availableTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button(action: {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }) {
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(selectedTags.contains(tag) ? .white : Theme.colorForTag(tag))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(selectedTags.contains(tag) ? Theme.colorForTag(tag) : Theme.colorForTag(tag).opacity(0.15))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, Theme.contentPadding)
                }
                .frame(height: 28)
            }
        }
        .padding(.vertical, 8)
    }

    private func createTodo() {
        if !newTodoTitle.isEmpty {
            // Parse hashtags from title
            let (cleanTitle, parsedTags) = parseHashtags(from: newTodoTitle)

            // Combine parsed tags with selected tags
            var allTags = Array(selectedTags)
            for tag in parsedTags {
                if !allTags.contains(tag) {
                    allTags.append(tag)
                }
            }

            let todo = Todo(
                title: cleanTitle,
                isCompleted: false,
                tags: allTags,
                priority: newTodoPriority
            )
            todoList.addTodo(todo)
            newTodoTitle = ""
            selectedTags.removeAll()
            newTodoPriority = .urgent
        }
    }

    private func parseHashtags(from text: String) -> (cleanTitle: String, tags: [String]) {
        let words = text.components(separatedBy: " ")
        var cleanWords: [String] = []
        var tags: [String] = []

        for word in words {
            if word.hasPrefix("#") && word.count > 1 {
                let tag = String(word.dropFirst())
                tags.append(tag)
            } else {
                cleanWords.append(word)
            }
        }

        return (cleanWords.joined(separator: " "), tags)
    }
}

// Quotes section for motivational text
struct QuotesSection: View {
    @ObservedObject var todoList: TodoList
    @State private var currentIndex: Int = 0
    @State private var isEditing: Bool = false
    @State private var isCollapsed: Bool = false
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 0 : 8) {
            // Header
            HStack(spacing: 6) {
                Button(action: {
                    withAnimation(Theme.Animation.quickFade) {
                        isCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 12)
                }
                .buttonStyle(PlainButtonStyle())

                Image(systemName: "quote.opening")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.purple)

                Text("Quotes")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.text)

                if isCollapsed && !todoList.quotes.isEmpty {
                    Text("(\(todoList.quotes.count))")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                }

                Spacer()

                if !isCollapsed {
                    if todoList.quotes.count > 1 && !isEditing {
                        // Cycle button (only show if more than one quote)
                        Button(action: {
                            withAnimation(Theme.Animation.quickFade) {
                                currentIndex = (currentIndex + 1) % max(1, todoList.quotes.count)
                            }
                        }) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.secondaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Edit button
                    Button(action: {
                        if isEditing {
                            // Save - use blank lines to separate quotes
                            todoList.quotes = editText
                                .components(separatedBy: "\n\n")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            todoList.saveTodos()
                            isEditing = false
                        } else {
                            // Join with blank lines for editing
                            editText = todoList.quotes.joined(separator: "\n\n")
                            isEditing = true
                        }
                    }) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(isEditing ? .green : Theme.secondaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if !isCollapsed {
                if isEditing {
                    // Edit mode - expands with content
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $editText)
                            .font(.system(size: 11))
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                            .frame(minHeight: 60, maxHeight: 200)
                            .focused($isFocused)
                            .onAppear { isFocused = true }

                        Text("One quote per line")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.secondaryText.opacity(0.7))
                    }
                } else if todoList.quotes.isEmpty {
                    Text("No quotes yet. Click edit to add some.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                        .italic()
                } else {
                    // Display current quote - expands naturally
                    // Safe access: clamp index and verify array is not empty
                    let quotes = todoList.quotes
                    if !quotes.isEmpty {
                        let safeIndex = min(max(0, currentIndex), quotes.count - 1)
                        Text(quotes[safeIndex])
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .italic()
                            .foregroundColor(Theme.text.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .fill(Color.purple.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                        .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                )
        )
        .animation(Theme.Animation.quickFade, value: isEditing)
        .animation(Theme.Animation.quickFade, value: isCollapsed)
    }
}

// Prominent sticky Top 5 section
struct Top5WeekSection: View {
    @ObservedObject var todoList: TodoList

    private let sectionColor = Color.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header matching Urgent/Normal style
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(sectionColor)

                Text("Top 5 of the Week")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)

                Text("\(todoList.top5Todos.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(sectionColor))

                Spacer()
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.vertical, 12)
            .background(sectionColor.opacity(0.05))

            // Colored line under header
            Rectangle()
                .fill(sectionColor.opacity(0.5))
                .frame(height: 2)

            // Items list
            VStack(spacing: 0) {
                ForEach(Array(todoList.top5Todos.enumerated()), id: \.element.id) { index, todo in
                    Top5ItemRow(todoList: todoList, todo: todo, rank: index + 1)
                }
            }
            .padding(.vertical, 2)
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(Theme.cornerRadiusMd)
        .overlay(
            Rectangle()
                .fill(sectionColor)
                .frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .stroke(sectionColor.opacity(0.15), lineWidth: 1)
        )
        .padding(.top, 6)
        .padding(.bottom, 16)
        .padding(.horizontal, Theme.contentPadding)
    }
}

// Compact row for Top 5 items
struct Top5ItemRow: View {
    @ObservedObject var todoList: TodoList
    let todo: Todo
    let rank: Int
    @State private var isHovered: Bool = false

    private let accentColor = Color.blue

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: { todoList.toggleTop5Todo(todo) }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(todo.isCompleted ? .green : Theme.secondaryText)
            }
            .buttonStyle(PlainButtonStyle())

            // Title
            Text(todo.title)
                .font(Theme.bodyFont)
                .foregroundColor(todo.isCompleted ? Theme.secondaryText : Theme.text)
                .strikethrough(todo.isCompleted)
                .lineLimit(1)

            Spacer()

            // First tag only (compact)
            if let firstTag = todo.tags.first {
                Text("#\(firstTag)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.colorForTag(firstTag))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? accentColor.opacity(0.06) : Color.clear)
        )
        .animation(Theme.Animation.quickFade, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct TodoListSections: View {
    @ObservedObject var todoList: TodoList
    var excludeTop5: Bool = false

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
            // Consider a todo untagged if it has no tags
            todo.tags.isEmpty
        }
        
        let taggedTodos = filteredTodos.filter { todo in
            // Consider a todo tagged if it has at least one tag
            !todo.tags.isEmpty
        }
        
        // Group tagged todos by their primary tag (first tag, or "today" if it exists)
        let groupedTodos = Dictionary(grouping: taggedTodos) { todo -> String in
            // Prioritize "today" tag if it exists, otherwise use first tag
            return todo.tags.first { $0.lowercased() == "today" } ?? todo.tags.first ?? "uncategorized"
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
            // Top 5 of the week section (only if not excluded - shown in sticky header instead)
            if !excludeTop5 && !todoList.top5Todos.isEmpty {
                TodoListSection(todoList: todoList, priority: nil, todos: todoList.top5Todos, customTitle: "🗓️ Top 5 of the week")
            }
            ForEach([Priority.urgent, Priority.normal, Priority.whenTime], id: \.self) { priority in
                let todos = filterAndSortTodos(for: priority)
                if !todos.isEmpty {
                    TodoListSection(todoList: todoList, priority: priority, todos: todos, customTitle: nil)
                }
            }

            // Completed section
            let completedTodos = todoList.todos.filter { $0.isCompleted }
            if !completedTodos.isEmpty {
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
        .padding(.bottom)
    }
}

struct TodoListSection: View {
    let todoList: TodoList
    let priority: Priority?
    let todos: [Todo]
    let customTitle: String?

    private var sectionColor: Color {
        if let priority = priority {
            switch priority {
            case .urgent: return .red
            case .normal: return .blue
            case .whenTime: return .gray
            }
        }
        return .green // Completed
    }

    var title: String {
        if let customTitle = customTitle {
            return customTitle
        }
        if let priority = priority {
            switch priority {
            case .urgent:
                return "Urgent"
            case .normal:
                return "Normal"
            case .whenTime:
                return "When there's time"
            }
        } else {
            return "Completed"
        }
    }

    var body: some View {
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Section header with colored accent
                HStack(spacing: 10) {
                    // Icon for priority sections
                    if let priority = priority {
                        Image(systemName: priority == .urgent ? "exclamationmark.circle.fill" : (priority == .normal ? "circle.fill" : "clock"))
                            .font(.system(size: 14))
                            .foregroundColor(sectionColor)
                    } else if customTitle == nil {
                        // Completed section
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(sectionColor)
                    } else {
                        Circle()
                            .fill(sectionColor)
                            .frame(width: 10, height: 10)
                    }

                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(priority == .urgent ? sectionColor : Theme.text)

                    Text("\(todos.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(sectionColor)
                        )

                    Spacer()

                    if priority == nil && customTitle == nil {
                        Button(action: { todoList.moveAllCompletedToDeleted() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                Text("Clear")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.vertical, 12)
                .background(
                    sectionColor.opacity(priority == .urgent ? 0.1 : 0.05)
                )

                // Colored line under header
                Rectangle()
                    .fill(sectionColor.opacity(0.5))
                    .frame(height: 2)

                // Todo items grouped by primary tag
                LazyVStack(spacing: 0) {
                    ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                        // Check if this is a new tag group
                        let currentTag = todo.tags.first
                        let previousTag = index > 0 ? todos[index - 1].tags.first : nil

                        if index > 0 && currentTag != previousTag {
                            // Divider between tag groups
                            Rectangle()
                                .fill(Theme.divider)
                                .frame(height: 1)
                                .padding(.horizontal, Theme.contentPadding)
                                .padding(.vertical, 4)
                        }

                        TodoItemView(todoList: todoList, todo: todo, isTop5: customTitle == "🗓️ Top 5 of the week")
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(Theme.cornerRadiusMd)
            .overlay(
                Rectangle()
                    .fill(sectionColor)
                    .frame(width: 3),
                alignment: .leading
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                    .stroke(sectionColor.opacity(0.15), lineWidth: 1)
            )
            .padding(.vertical, 6)
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

    // Pre-compute todos grouped by tag to avoid O(n*m) filtering
    private var todosByTag: [String: [Todo]] {
        var result: [String: [Todo]] = [:]
        for todo in todoList.todos {
            for tag in todo.tags {
                result[tag, default: []].append(todo)
            }
        }
        return result
    }

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
                            TagPillView(tag: tag, size: .small)
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
                    ForEach(todosByTag[tag] ?? []) { todo in
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

// Add a resizable bar between columns with visual feedback
struct ResizableBar: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            // Wider invisible hit area
            Rectangle()
                .fill(Color.clear)
                .frame(width: 12)
                .contentShape(Rectangle())

            // Visible indicator - always show subtle line
            RoundedRectangle(cornerRadius: 1)
                .fill(isDragging ? Theme.accent : (isHovered ? Theme.accent.opacity(0.5) : Theme.divider.opacity(0.5)))
                .frame(width: isDragging ? 3 : (isHovered ? 2 : 1))
                .animation(Theme.Animation.quickFade, value: isHovered)
                .animation(Theme.Animation.quickFade, value: isDragging)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else if !isDragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    let newWidth = width + value.translation.width
                    width = min(max(minWidth, newWidth), maxWidth)
                }
                .onEnded { _ in
                    isDragging = false
                    if !isHovered {
                        NSCursor.pop()
                    }
                }
        )
    }
} 