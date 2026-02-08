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
        VStack(spacing: 0) {
            // Header with title and edit button
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent)
                Text("Goals")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text)

                Spacer()

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
                    HStack(spacing: 4) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 10, weight: .medium))
                        Text(isEditing ? "Done" : "Edit")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isEditing ? .white : Theme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isEditing ? Color.green : Theme.secondaryBackground)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .help(isEditing ? "Save changes" : "Edit goals")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardBackground)

            Divider()

            if isEditing {
                // Edit mode - Clean text editor
                TextEditor(text: $editText)
                    .font(.system(size: 13))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .focused($isFocused)
                    .onAppear {
                        DispatchQueue.main.async {
                            editText = todoList.goals
                            isFocused = true
                        }
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
                            Text("Click Edit to add your goals")
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
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadius)
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

                            GoalItemText(text: item)
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
                .fill(Theme.cardBackground)
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

// Helper view to render goal item text with bold colored tags inline
struct GoalItemText: View {
    let text: String

    var body: some View {
        buildText()
            .font(.system(size: 13))
            .foregroundColor(Theme.text.opacity(0.85))
    }

    private func buildText() -> Text {
        var result = Text("")
        let words = text.split(separator: " ", omittingEmptySubsequences: false)

        for (index, word) in words.enumerated() {
            let wordStr = String(word)
            let prefix = index > 0 ? " " : ""

            if wordStr.hasPrefix("#") && wordStr.count > 1 {
                let tagName = String(wordStr.dropFirst())
                result = result + Text(prefix) + Text("#\(tagName)")
                    .bold()
                    .foregroundColor(Theme.colorForTag(tagName))
            } else {
                result = result + Text(prefix + wordStr)
            }
        }

        return result
    }
}

// Live markdown preview for the editor
struct MarkdownPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { _, line in
                lineView(for: line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum LineType {
        case header(level: Int)
        case bullet
        case text
    }

    private struct ParsedLine {
        let type: LineType
        let content: String
    }

    private func parseLines() -> [ParsedLine] {
        text.components(separatedBy: .newlines).compactMap { line -> ParsedLine? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            // Check for headers
            if trimmed.hasPrefix("###") {
                return ParsedLine(type: .header(level: 3), content: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("##") {
                return ParsedLine(type: .header(level: 2), content: String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("#") && !trimmed.hasPrefix("# ") == false {
                return ParsedLine(type: .header(level: 1), content: String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
            }
            // Bullets
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return ParsedLine(type: .bullet, content: String(trimmed.dropFirst(2)))
            }
            // Bold headers **text**
            else if trimmed.hasPrefix("**") {
                var content = String(trimmed.dropFirst(2))
                if let endIdx = content.range(of: "**") {
                    content = String(content[..<endIdx.lowerBound])
                }
                return ParsedLine(type: .header(level: 2), content: content)
            }

            return ParsedLine(type: .text, content: trimmed)
        }
    }

    @ViewBuilder
    private func lineView(for line: ParsedLine) -> some View {
        switch line.type {
        case .header(let level):
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent)
                    .frame(width: 3, height: level == 1 ? 16 : 14)
                renderContent(line.content)
                    .font(.system(size: level == 1 ? 14 : 12, weight: .semibold))
            }
            .padding(.top, 6)

        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .padding(.top, 5)
                renderContent(line.content)
                    .font(.system(size: 11))
            }
            .padding(.leading, 8)

        case .text:
            renderContent(line.content)
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private func renderContent(_ text: String) -> some View {
        // Simple text with #tag coloring
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        HStack(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                let wordStr = String(word)
                if wordStr.hasPrefix("#") && wordStr.count > 1 {
                    let tagName = String(wordStr.dropFirst())
                    Text(wordStr)
                        .foregroundColor(Theme.colorForTag(tagName))
                        .fontWeight(.semibold)
                } else if wordStr.hasPrefix("**") && wordStr.hasSuffix("**") && wordStr.count > 4 {
                    let boldText = String(wordStr.dropFirst(2).dropLast(2))
                    Text(boldText)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.text)
                } else {
                    Text(wordStr)
                        .foregroundColor(Theme.text)
                }
            }
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
        .background(Theme.cardBackground) // Adapts to light/dark mode
        .cornerRadius(8)
    }
}

struct TodoListView: View {
    @ObservedObject var todoList: TodoList
    @State private var newTodoTitle = ""
    @State private var newTodoPriority: Priority = .thisWeek
    @State private var leftColumnWidth: CGFloat = 380
    @State private var isInMindMapMode: Bool = false  // Toggle between list and mind map views
    @State private var showingSettings: Bool = false  // Settings sheet
    @State private var groupingMode: GroupingMode = .contextMode  // Grouping mode toggle
    @State private var searchText: String = ""  // Search filter
    @State private var isSearching: Bool = false  // Show search bar

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()
            VStack(spacing: 0) {
                // Top Bar
                HStack(spacing: 12) {
                    // File menu
                    Menu {
                        Button(action: { todoList.openFile() }) {
                            Label("Open File...", systemImage: "folder.badge.plus")
                        }
                        Button(action: { todoList.createNewFile(demo: false) }) {
                            Label("New Blank File...", systemImage: "doc.badge.plus")
                        }
                        Button(action: { todoList.createNewFile(demo: true) }) {
                            Label("New Demo File...", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                    .help("File options")

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

                    // Grouping mode toggle (only in list mode)
                    if !isInMindMapMode {
                        Button(action: {
                            withAnimation(Theme.Animation.quickFade) {
                                groupingMode = (groupingMode == .contextMode) ? .tagMode : .contextMode
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: groupingMode == .contextMode ? "square.grid.2x2" : "tag")
                                    .font(.system(size: 11, weight: .medium))
                                Text(groupingMode == .contextMode ? "Context" : "Tags")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(Theme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Theme.secondaryBackground)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(groupingMode == .contextMode ? "Switch to Tag grouping" : "Switch to Context grouping")
                    }

                    // Search button
                    Button(action: {
                        withAnimation(Theme.Animation.quickFade) {
                            isSearching.toggle()
                            if !isSearching {
                                searchText = ""
                            }
                        }
                    }) {
                        Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isSearching ? Theme.accent : Theme.secondaryText)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .fill(isSearching ? Theme.accent.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(isSearching ? "Close Search" : "Search Todos")
                    .keyboardShortcut("f", modifiers: .command)

                    // Settings button
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Settings")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                // Search Bar (when active)
                if isSearching {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.secondaryText)
                        TextField("Search todos...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.secondaryText)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.secondaryBackground)
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }

                // Main Content - Either Mind Map or List View
                if isInMindMapMode {
                    // Mind Map View
                    MindMapView(todoList: todoList)
                        .transition(.opacity)
                } else {
                    // List View with Resizable Columns
                    HStack(spacing: 0) {
                        // Left Column - Goals
                        VStack(spacing: 0) {
                            EditableGoalsView(todoList: todoList)
                                .padding(.horizontal, Theme.contentPadding)
                                .padding(.top, Theme.contentPadding)
                        }
                        .frame(width: leftColumnWidth)

                        // Resizable divider for Goals
                        ResizableBar(width: $leftColumnWidth, minWidth: 200, maxWidth: 500)

                        // Right Column - Todos
                        VStack(spacing: 0) {

                            // New Todo Input
                            NewTodoInput(
                                todoList: todoList,
                                newTodoTitle: $newTodoTitle,
                                newTodoPriority: $newTodoPriority
                            )

                            // Sticky Top 5 Section (always visible)
                            Top5WeekSection(todoList: todoList)
                                .padding(.top, 8)

                            // Scrollable todo list (without Top 5)
                            ScrollView {
                                TodoListSections(todoList: todoList, excludeTop5: true, groupingMode: $groupingMode, searchText: searchText)
                            }
                            .scrollIndicators(.hidden)
                            .clipped()
                            .padding(.horizontal, Theme.contentPadding)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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
            newTodoPriority = .thisWeek
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
            
            Button(action: { todoList.createNewFile(demo: false) }) {
                Image(systemName: "doc.badge.plus")
            }
            .help("New blank file")

            Button(action: { todoList.createNewFile(demo: true) }) {
                Image(systemName: "sparkles")
            }
            .help("New demo file (with sample todos + AI demo mode)")
            
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

    // AI Suggestion state
    @State private var suggestedContext: String? = nil
    @State private var isLoadingSuggestions: Bool = false
    @State private var suggestionError: String? = nil
    @State private var showSuggestions: Bool = false

    private var availableTags: [String] {
        todoList.allTags.sorted()
    }

    private var hasAPIKey: Bool {
        APIKeyManager.shared.hasAPIKey
    }

    var body: some View {
        VStack(spacing: 6) {
            // Main input row
            HStack(spacing: 10) {
                // Priority indicator - cycles through thisWeek -> urgent -> normal
                Image(systemName: newTodoPriority.icon)
                    .font(.system(size: 14))
                    .foregroundColor(newTodoPriority.color)
                    .onTapGesture {
                        withAnimation(Theme.Animation.microSpring) {
                            // Cycle through priorities: thisWeek -> urgent -> normal -> thisWeek
                            switch newTodoPriority {
                            case .thisWeek:
                                newTodoPriority = .urgent
                            case .urgent:
                                newTodoPriority = .normal
                            case .normal:
                                newTodoPriority = .thisWeek
                            }
                        }
                    }

                TextField("Add a new todo...", text: $newTodoTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isTextFieldFocused)
                    .onSubmit(createTodo)
                    .onChange(of: newTodoTitle) { _, newValue in
                        // Reset suggestions when title changes significantly
                        if showSuggestions && newValue.count < 3 {
                            showSuggestions = false
                            suggestedContext = nil
                        }
                    }

                // AI Suggest button (only show if API key exists and title has content)
                if hasAPIKey && newTodoTitle.count >= 3 {
                    Button(action: fetchSuggestions) {
                        if isLoadingSuggestions {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundColor(showSuggestions ? Theme.accent : Theme.secondaryText)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Suggest tags with AI")
                    .disabled(isLoadingSuggestions)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                    .stroke(isTextFieldFocused ? Theme.accent.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, Theme.contentPadding)

            // AI Suggestions row
            if showSuggestions && suggestedContext != nil {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.purple)

                    Text("Context:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.secondaryText)

                    // Context tag suggestion
                    if let context = suggestedContext {
                        SuggestionChip(
                            tag: context,
                            isSelected: selectedTags.contains(context),
                            isContext: true
                        ) {
                            toggleTag(context)
                        }
                    }

                    Spacer()

                    // Dismiss suggestions
                    Button(action: {
                        withAnimation(Theme.Animation.quickFade) {
                            showSuggestions = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.05))
                .cornerRadius(Theme.cornerRadius)
                .padding(.horizontal, Theme.contentPadding)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Error message
            if let error = suggestionError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.horizontal, Theme.contentPadding)
            }

            // Quick tag buttons - always show section
            VStack(alignment: .leading, spacing: 4) {
                if !selectedTags.isEmpty {
                    // Show selected tags prominently
                    HStack(spacing: 4) {
                        Text("Tags:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                        ForEach(Array(selectedTags).sorted(), id: \.self) { tag in
                            HStack(spacing: 2) {
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .semibold))
                                Button(action: { selectedTags.remove(tag) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.colorForTag(tag)))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Theme.contentPadding)
                }

                if !availableTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if selectedTags.isEmpty {
                                Text("Tags:")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Theme.secondaryText)
                            }
                            ForEach(availableTags.filter { !selectedTags.contains($0) }, id: \.self) { tag in
                                Button(action: {
                                    toggleTag(tag)
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 8, weight: .bold))
                                        Text("#\(tag)")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(Theme.colorForTag(tag))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.colorForTag(tag).opacity(0.12))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, Theme.contentPadding)
                    }
                    .frame(height: 28)
                }
            }
        }
        .padding(.vertical, 8)
        .animation(Theme.Animation.quickFade, value: showSuggestions)
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func fetchSuggestions() {
        guard !isLoadingSuggestions else { return }

        isLoadingSuggestions = true
        suggestionError = nil

        Task {
            do {
                let suggestion = try await ClaudeCategorizationService.shared.suggestTags(
                    todoText: newTodoTitle,
                    existingTags: todoList.allTags,
                    goalSections: []
                )

                await MainActor.run {
                    suggestedContext = suggestion.context
                    // Auto-apply the context tag if found
                    if let context = suggestion.context {
                        selectedTags.insert(context)
                    }
                    showSuggestions = suggestion.context != nil
                    isLoadingSuggestions = false
                }
            } catch {
                await MainActor.run {
                    suggestionError = error.localizedDescription
                    isLoadingSuggestions = false
                }
            }
        }
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
            suggestedContext = nil
            showSuggestions = false
            newTodoPriority = .thisWeek
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

// Suggestion chip for AI-suggested tags
struct SuggestionChip: View {
    let tag: String
    let isSelected: Bool
    let isContext: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if isContext {
                    Image(systemName: iconForContext(tag))
                        .font(.system(size: 8))
                }
                Text("#\(tag)")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : Theme.colorForTag(tag))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.colorForTag(tag) : Theme.colorForTag(tag).opacity(0.2))
            )
            .overlay(
                Capsule()
                    .stroke(isContext ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconForContext(_ context: String) -> String {
        switch context.lowercased() {
        case "prep": return "calendar"
        case "reply": return "arrowshape.turn.up.left"
        case "deep": return "brain.head.profile"
        case "waiting": return "hourglass"
        default: return "tag"
        }
    }
}


// Prominent sticky Top 5 section
struct Top5WeekSection: View {
    @ObservedObject var todoList: TodoList
    @State private var isAddingNew = false
    @State private var newItemTitle = ""
    @FocusState private var addFieldFocused: Bool

    private let sectionColor = Color.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(sectionColor)
                    .frame(width: 16, height: 16)

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

                if !todoList.top5Todos.isEmpty {
                    Button(action: { todoList.clearTop5() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Clear Top 5 and start fresh")
                }

                if todoList.top5Todos.count < 5 {
                    Button(action: {
                        isAddingNew = true
                        addFieldFocused = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(sectionColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Add item to Top 5")
                }
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

                // Inline add field or empty state
                if isAddingNew {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(sectionColor.opacity(0.5))

                        TextField("New Top 5 item...", text: $newItemTitle)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(Theme.bodyFont)
                            .focused($addFieldFocused)
                            .onSubmit {
                                addNewItem()
                            }

                        Button("Cancel") {
                            isAddingNew = false
                            newItemTitle = ""
                        }
                        .font(.caption)
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                } else if todoList.top5Todos.isEmpty {
                    Button(action: {
                        isAddingNew = true
                        addFieldFocused = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.dashed")
                                .font(.system(size: 13))
                            Text("What are your top priorities this week?")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .background(Theme.cardBackground)
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

    private func addNewItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let todo = Todo(title: title, priority: .thisWeek)
        todoList.addTop5Todo(todo)
        newItemTitle = ""
        isAddingNew = false
    }
}

// Compact row for Top 5 items with inline editing
struct Top5ItemRow: View {
    @ObservedObject var todoList: TodoList
    @State var todo: Todo
    let rank: Int
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @FocusState private var editFocused: Bool

    // AI suggestion state
    @State private var isLoadingAI = false
    @State private var showingAISuggestion = false
    @State private var suggestedContext: String? = nil

    private let accentColor = Color.blue

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: {
                todoList.toggleTop5Todo(todo)
                if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                    todo = updated
                }
            }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(todo.isCompleted ? .green : Theme.secondaryText)
            }
            .buttonStyle(PlainButtonStyle())

            if isEditing {
                TextField("Title", text: $editedTitle)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(Theme.bodyFont)
                    .focused($editFocused)
                    .onSubmit { saveEdit() }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Theme.background)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(accentColor.opacity(0.5), lineWidth: 1)
                    )
            } else {
                // Title
                Text(todo.title)
                    .font(Theme.bodyFont)
                    .foregroundColor(todo.isCompleted ? Theme.secondaryText : Theme.text)
                    .strikethrough(todo.isCompleted)
                    .lineLimit(1)
            }

            Spacer()

            // Tags (compact)
            if !isEditing {
                ForEach(todo.tags.prefix(2), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.colorForTag(tag))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isEditing ? accentColor.opacity(0.08) : (isHovered ? accentColor.opacity(0.06) : Color.clear))
        )
        .animation(Theme.Animation.quickFade, value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .gesture(
            TapGesture(count: 2).onEnded {
                editedTitle = todo.title
                isEditing = true
                editFocused = true
            }
        )
        .onChange(of: editFocused) { _, focused in
            if !focused && isEditing { saveEdit() }
        }
        .contextMenu {
            // Edit
            Button {
                editedTitle = todo.title
                isEditing = true
                editFocused = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            // Move up / down
            Button {
                todoList.moveTop5Todo(todo, direction: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(todoList.top5Todos.first?.id == todo.id)

            Button {
                todoList.moveTop5Todo(todo, direction: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(todoList.top5Todos.last?.id == todo.id)

            Divider()

            // Context tags
            Menu("Context") {
                let contextManager = ContextConfigManager.shared
                ForEach(contextManager.contexts, id: \.id) { context in
                    let hasContext = todo.tags.contains { $0.lowercased() == context.id.lowercased() }
                    Button {
                        if hasContext {
                            todoList.removeTagFromTop5Todo(todo, tag: context.id)
                        } else {
                            todoList.addTagToTop5Todo(todo, tag: context.id)
                        }
                        if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                            todo = updated
                        }
                    } label: {
                        Label {
                            Text(context.name)
                        } icon: {
                            Image(systemName: hasContext ? "checkmark.circle.fill" : context.icon)
                        }
                    }
                }
            }

            // Tags
            Menu("Tags") {
                if !todo.tags.isEmpty {
                    ForEach(todo.tags, id: \.self) { tag in
                        Button {
                            todoList.removeTagFromTop5Todo(todo, tag: tag)
                            if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                                todo = updated
                            }
                        } label: {
                            Label("Remove #\(tag)", systemImage: "minus.circle")
                        }
                    }
                    Divider()
                }
                let availableTags = todoList.allTags.filter { !todo.tags.contains($0) }
                ForEach(availableTags, id: \.self) { tag in
                    Button {
                        todoList.addTagToTop5Todo(todo, tag: tag)
                        if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                            todo = updated
                        }
                    } label: {
                        Label("Add #\(tag)", systemImage: "plus.circle")
                    }
                }
            }

            // AI Auto-tag
            if APIKeyManager.shared.hasAPIKey {
                Button {
                    fetchAISuggestion()
                } label: {
                    Label(isLoadingAI ? "Analyzing..." : "Auto-tag with AI", systemImage: "sparkles")
                }
                .disabled(isLoadingAI)
            }

            Divider()

            // Complete / Uncomplete
            Button {
                todoList.toggleTop5Todo(todo)
                if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                    todo = updated
                }
            } label: {
                Label(todo.isCompleted ? "Mark Incomplete" : "Mark Complete", systemImage: todo.isCompleted ? "circle" : "checkmark.circle")
            }

            // Remove from Top 5
            Button(role: .destructive) {
                todoList.deleteTop5Todo(todo)
            } label: {
                Label("Remove from Top 5", systemImage: "star.slash")
            }
        }
        .alert("AI Suggestion", isPresented: $showingAISuggestion) {
            if let context = suggestedContext {
                Button("Add #\(context)") {
                    todoList.addTagToTop5Todo(todo, tag: context)
                    if let updated = todoList.top5Todos.first(where: { $0.id == todo.id }) {
                        self.todo = updated
                    }
                    suggestedContext = nil
                }
            }
            Button("Cancel", role: .cancel) { suggestedContext = nil }
        } message: {
            if let context = suggestedContext {
                Text("Add context tag #\(context) to this todo?")
            } else {
                Text("No context suggestion available for this todo.")
            }
        }
    }

    private func saveEdit() {
        let title = editedTitle.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            var updated = todo
            updated.title = title
            todoList.updateTop5Todo(updated)
            todo = updated
        }
        isEditing = false
    }

    private func fetchAISuggestion() {
        guard !isLoadingAI else { return }
        isLoadingAI = true
        Task {
            do {
                let suggestion = try await ClaudeCategorizationService.shared.suggestTags(
                    todoText: todo.title,
                    existingTags: todoList.allTags
                )
                await MainActor.run {
                    isLoadingAI = false
                    suggestedContext = suggestion.context
                    showingAISuggestion = true
                }
            } catch {
                await MainActor.run {
                    isLoadingAI = false
                    suggestedContext = nil
                    showingAISuggestion = true
                }
            }
        }
    }
}

// Grouping mode for todo list
enum GroupingMode: String, CaseIterable {
    case contextMode = "Context"   // Group by context tags (prep, reply, deep, waiting)
    case tagMode = "Tags"          // Group by any tags, sorted by frequency
}

// Context section configuration
struct ContextSection: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let contextTag: String? // nil for special sections like Today, Urgent, Other

    static let today = ContextSection(id: "today", title: "Today", icon: "pin.fill", color: Theme.todayTagColor, contextTag: nil)
    static let thisWeek = ContextSection(id: "thisweek", title: "This Week", icon: "calendar.badge.exclamationmark", color: Theme.thisWeekTagColor, contextTag: nil)
    static let urgent = ContextSection(id: "urgent", title: "Urgent", icon: "flame.fill", color: Theme.urgentTagColor, contextTag: nil)
    static let other = ContextSection(id: "other", title: "Other", icon: "tray", color: .gray, contextTag: nil)
    static let completed = ContextSection(id: "completed", title: "Completed", icon: "checkmark.circle.fill", color: .green, contextTag: nil)

    // Get context tags from configuration
    static var contextTags: [String] {
        ContextConfigManager.shared.contextTags
    }

    // Build context sections from configuration
    static var contextSections: [ContextSection] {
        var sections = ContextConfigManager.shared.contexts.map { config in
            ContextSection(
                id: config.id,
                title: config.name,
                icon: config.icon,
                color: config.color,
                contextTag: config.id
            )
        }
        sections.append(.other)
        return sections
    }

    // Get a section for a specific context tag
    static func section(for contextTag: String) -> ContextSection? {
        if let config = ContextConfigManager.shared.context(for: contextTag) {
            return ContextSection(
                id: config.id,
                title: config.name,
                icon: config.icon,
                color: config.color,
                contextTag: config.id
            )
        }
        return nil
    }
}

struct TodoListSections: View {
    @ObservedObject var todoList: TodoList
    var excludeTop5: Bool = false
    @Binding var groupingMode: GroupingMode
    var searchText: String = ""

    // MARK: - Performance Optimized Data Structures

    /// Pre-computed todo metadata for O(1) lookups during filtering
    private struct TodoMeta {
        let todo: Todo
        let titleLower: String
        let tagsLower: Set<String>
        let hasToday: Bool
        let hasThisWeek: Bool
        let hasUrgent: Bool
        let hasContextTag: Bool
        let primaryContextTag: String?
    }

    /// Single-pass categorization result
    private struct CategorizedTodos {
        var today: [TodoMeta] = []
        var thisWeek: [TodoMeta] = []
        var urgent: [TodoMeta] = []
        var normal: [TodoMeta] = []
        var completed: [TodoMeta] = []
    }

    // Pre-compute search filter once
    private var searchFilter: String {
        searchText.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Pre-process all todos once with lowercase values and tag flags
    private var processedTodos: [TodoMeta] {
        let contextManager = ContextConfigManager.shared
        let filter = searchFilter

        return todoList.todos.compactMap { todo in
            let titleLower = todo.title.lowercased()
            let tagsLower = Set(todo.tags.map { $0.lowercased() })

            // Search filter check (early exit)
            if !filter.isEmpty {
                let matchesTitle = titleLower.contains(filter)
                let matchesTags = tagsLower.contains { $0.contains(filter) }
                if !matchesTitle && !matchesTags { return nil }
            }

            // Pre-compute tag flags (O(1) set lookups)
            let hasToday = tagsLower.contains("today")
            let hasThisWeek = tagsLower.contains("thisweek")
            let hasUrgent = tagsLower.contains("urgent")

            // Find primary context tag
            var primaryContextTag: String? = nil
            var hasContextTag = false
            for tag in tagsLower {
                if contextManager.isContextTag(tag) {
                    hasContextTag = true
                    if primaryContextTag == nil {
                        primaryContextTag = tag
                    }
                }
            }

            return TodoMeta(
                todo: todo,
                titleLower: titleLower,
                tagsLower: tagsLower,
                hasToday: hasToday,
                hasThisWeek: hasThisWeek,
                hasUrgent: hasUrgent,
                hasContextTag: hasContextTag,
                primaryContextTag: primaryContextTag
            )
        }
    }

    /// Single-pass categorization of all todos
    private var categorizedTodos: CategorizedTodos {
        var result = CategorizedTodos()

        for meta in processedTodos {
            if meta.todo.isCompleted {
                result.completed.append(meta)
                continue
            }

            // Priority order: today > thisWeek > urgent > normal
            if meta.hasToday {
                result.today.append(meta)
            } else if meta.hasThisWeek || meta.todo.priority == .thisWeek {
                result.thisWeek.append(meta)
            } else if meta.hasUrgent || meta.todo.priority == .urgent {
                result.urgent.append(meta)
            } else {
                result.normal.append(meta)
            }
        }

        return result
    }

    /// Sort todos by pre-computed lowercase title
    private func sortByTitle(_ metas: [TodoMeta]) -> [Todo] {
        metas.sorted { $0.titleLower < $1.titleLower }.map { $0.todo }
    }

    // MARK: - Optimized Accessors

    private func todosForUrgency(_ urgencyType: String) -> [Todo] {
        let cats = categorizedTodos
        switch urgencyType {
        case "today": return sortByTitle(cats.today)
        case "thisweek": return sortByTitle(cats.thisWeek)
        case "urgent": return sortByTitle(cats.urgent)
        default: return []
        }
    }

    private func todosByContext(from todos: [Todo], groupOtherByTags: Bool = false) -> [(context: ContextSection, todos: [Todo])] {
        // Build a map of todo IDs to their metadata for O(1) lookup
        let metaMap = Dictionary(uniqueKeysWithValues: processedTodos.map { ($0.todo.id, $0) })
        var result: [(context: ContextSection, todos: [Todo])] = []

        for contextSection in ContextSection.contextSections {
            let contextTodos: [Todo]
            if contextSection.id == "other" {
                contextTodos = todos.filter { todo in
                    guard let meta = metaMap[todo.id] else { return false }
                    return !meta.hasContextTag
                }
            } else if let contextTag = contextSection.contextTag {
                let ctLower = contextTag.lowercased()
                contextTodos = todos.filter { todo in
                    guard let meta = metaMap[todo.id] else { return false }
                    return meta.tagsLower.contains(ctLower)
                }
            } else {
                contextTodos = []
            }

            if !contextTodos.isEmpty {
                // Use pre-computed lowercase for sorting
                let sorted = contextTodos.sorted { t1, t2 in
                    let m1 = metaMap[t1.id]?.titleLower ?? ""
                    let m2 = metaMap[t2.id]?.titleLower ?? ""
                    return m1 < m2
                }
                result.append((contextSection, sorted))
            }
        }

        return result
    }

    private func todosForSection(_ section: ContextSection) -> [Todo] {
        let cats = categorizedTodos

        func sortMetas(_ metas: [TodoMeta]) -> [Todo] {
            metas.sorted { $0.titleLower < $1.titleLower }.map { $0.todo }
        }

        switch section.id {
        case "today":
            return sortMetas(cats.today)

        case "thisweek":
            return sortMetas(cats.thisWeek)

        case "urgent":
            return sortMetas(cats.urgent)

        case "prep", "reply", "deep", "waiting":
            guard let contextTag = section.contextTag else { return [] }
            let ctLower = contextTag.lowercased()
            let filtered = cats.normal.filter { $0.tagsLower.contains(ctLower) }
            return sortMetas(filtered)

        case "other":
            let filtered = cats.normal.filter { !$0.hasContextTag }
            return sortMetas(filtered)

        case "completed":
            return sortMetas(cats.completed)

        default:
            return []
        }
    }

    // Legacy search function (kept for compatibility)
    private func matchesSearch(_ todo: Todo) -> Bool {
        guard !searchFilter.isEmpty else { return true }
        if todo.title.lowercased().contains(searchFilter) { return true }
        if todo.tags.contains(where: { $0.lowercased().contains(searchFilter) }) { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top 5 of the week section
            if !excludeTop5 && !todoList.top5Todos.isEmpty {
                ContextTodoSection(
                    todoList: todoList,
                    section: ContextSection(id: "top5", title: "Top 5 of the Week", icon: "star.fill", color: .blue, contextTag: nil),
                    todos: todoList.top5Todos,
                    isTop5: true
                )
            }

            if groupingMode == .contextMode {
                // CONTEXT MODE: Today/Urgent with context sub-groups
                contextModeView
            } else {
                // TAG MODE: Group by any tags, sorted by frequency
                tagModeView
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
                .background(Theme.cardBackground)
            }
        }
        .padding(.bottom)
    }

    // Context mode view - Today (flat), This Week, Urgent/Normal with context sub-groups
    @ViewBuilder
    private var contextModeView: some View {
        // Use pre-categorized todos (single-pass optimization)
        let cats = categorizedTodos

        // Today section - simple flat list, no context grouping
        let todayTodos = sortByTitle(cats.today)
        if !todayTodos.isEmpty {
            ContextTodoSection(
                todoList: todoList,
                section: .today,
                todos: todayTodos,
                isTop5: false
            )
        }

        // This Week section with context sub-groups
        let thisWeekTodos = sortByTitle(cats.thisWeek)
        if !thisWeekTodos.isEmpty {
            UrgencySectionWithContextGroups(
                todoList: todoList,
                urgencySection: .thisWeek,
                todosByContext: todosByContextOnly(from: thisWeekTodos)
            )
        }

        // Urgent section with context sub-groups
        let urgentTodos = sortByTitle(cats.urgent)
        if !urgentTodos.isEmpty {
            UrgencySectionWithContextGroups(
                todoList: todoList,
                urgencySection: .urgent,
                todosByContext: todosByContextOnly(from: urgentTodos)
            )
        }

        // Normal priority todos - with context sub-groups
        let normalTodos = sortByTitle(cats.normal)
        if !normalTodos.isEmpty {
            UrgencySectionWithContextGroups(
                todoList: todoList,
                urgencySection: ContextSection(id: "normal", title: "Normal", icon: "tray.full", color: .gray, contextTag: nil),
                todosByContext: todosByContextOnly(from: normalTodos)
            )
        }

        // Completed section
        let completedTodos = sortByTitle(cats.completed)
        if !completedTodos.isEmpty {
            ContextTodoSection(
                todoList: todoList,
                section: .completed,
                todos: completedTodos,
                isTop5: false
            )
        }
    }

    // Get todos grouped by context only - "Other" is a flat list (no tag headers)
    private func todosByContextOnly(from todos: [Todo]) -> [(context: ContextSection, todos: [Todo])] {
        var result: [(context: ContextSection, todos: [Todo])] = []

        // Build metadata map from pre-computed data for O(1) lookups
        let metaMap = Dictionary(uniqueKeysWithValues: processedTodos.map { ($0.todo.id, $0) })

        // Group by context tags using pre-computed lowercase tags
        for contextSection in ContextSection.contextSections {
            if contextSection.id == "other" {
                continue // Handle "Other" separately
            }
            if let contextTag = contextSection.contextTag {
                let ctLower = contextTag.lowercased()
                let contextTodos = todos.filter { todo in
                    metaMap[todo.id]?.tagsLower.contains(ctLower) ?? false
                }
                if !contextTodos.isEmpty {
                    // Sort using pre-computed lowercase titles
                    let sorted = contextTodos.sorted {
                        (metaMap[$0.id]?.titleLower ?? "") < (metaMap[$1.id]?.titleLower ?? "")
                    }
                    result.append((contextSection, sorted))
                }
            }
        }

        // "Other" - todos without context tags (using pre-computed flag)
        let otherTodos = todos.filter { todo in
            !(metaMap[todo.id]?.hasContextTag ?? true)
        }

        if !otherTodos.isEmpty {
            // Count tag frequency in single pass
            var tagCounts: [String: Int] = [:]
            var tagLowerMap: [String: String] = [:]  // Cache lowercase versions
            for todo in otherTodos {
                for tag in todo.tags {
                    tagCounts[tag, default: 0] += 1
                    if tagLowerMap[tag] == nil {
                        tagLowerMap[tag] = tag.lowercased()
                    }
                }
            }

            // Sort tags by frequency (descending), then alphabetically
            let sortedTags = tagCounts.keys.sorted { tag1, tag2 in
                let count1 = tagCounts[tag1] ?? 0
                let count2 = tagCounts[tag2] ?? 0
                if count1 != count2 { return count1 > count2 }
                return tagLowerMap[tag1, default: ""] < tagLowerMap[tag2, default: ""]
            }

            // Build tag index map for O(1) lookup instead of O(n) firstIndex
            let tagIndex = Dictionary(uniqueKeysWithValues: sortedTags.enumerated().map { ($1, $0) })

            // Assign each todo to its highest-priority (most frequent) tag
            var primaryTag: [UUID: String] = [:]
            var primaryTagIndex: [UUID: Int] = [:]  // Cache the index too
            for todo in otherTodos {
                for tag in sortedTags {
                    if todo.tags.contains(tag) {
                        primaryTag[todo.id] = tag
                        primaryTagIndex[todo.id] = tagIndex[tag] ?? Int.max
                        break
                    }
                }
            }

            // Sort todos: group by primary tag (in frequency order), then by title within group
            let sortedOther = otherTodos.sorted { todo1, todo2 in
                let idx1 = primaryTagIndex[todo1.id] ?? Int.max
                let idx2 = primaryTagIndex[todo2.id] ?? Int.max

                // Compare by tag priority
                if idx1 != idx2 { return idx1 < idx2 }

                // Same tag or both untagged - sort by title (using pre-computed lowercase)
                let title1 = metaMap[todo1.id]?.titleLower ?? ""
                let title2 = metaMap[todo2.id]?.titleLower ?? ""
                return title1 < title2
            }

            result.append((.other, sortedOther))
        }

        return result
    }

    // Compute tag groups for tag mode - each todo assigned to exactly one group
    // Excludes context tags (prep, reply, deep, waiting) - only shows actual tags
    private func computeTagGroups() -> [(tag: String?, todos: [Todo])] {
        let incompleteTodos = todoList.todos.filter { !$0.isCompleted && matchesSearch($0) }
        let contextManager = ContextConfigManager.shared

        // Single pass: count tags and cache non-context tags per todo
        var tagCounts: [String: Int] = [:]
        var tagLowerMap: [String: String] = [:]
        var todoNonContextTags: [UUID: [String]] = [:]

        for todo in incompleteTodos {
            var nonContextTags: [String] = []
            for tag in todo.tags {
                // O(1) context check
                if contextManager.isContextTag(tag) {
                    continue
                }
                nonContextTags.append(tag)
                tagCounts[tag, default: 0] += 1
                if tagLowerMap[tag] == nil {
                    tagLowerMap[tag] = tag.lowercased()
                }
            }
            todoNonContextTags[todo.id] = nonContextTags
        }

        // Sort tags by count (descending), then alphabetically
        let sortedTags = tagCounts.keys.sorted { tag1, tag2 in
            let count1 = tagCounts[tag1] ?? 0
            let count2 = tagCounts[tag2] ?? 0
            if count1 != count2 {
                return count1 > count2
            }
            return tagLowerMap[tag1, default: ""] < tagLowerMap[tag2, default: ""]
        }

        // Build tag index for O(1) lookup
        let tagIndex = Dictionary(uniqueKeysWithValues: sortedTags.enumerated().map { ($1, $0) })

        // Assign each todo to its highest-priority tag and group directly
        var todosByTag: [String: [Todo]] = [:]
        var untaggedTodos: [Todo] = []

        for todo in incompleteTodos {
            let nonContextTags = todoNonContextTags[todo.id] ?? []
            if nonContextTags.isEmpty {
                untaggedTodos.append(todo)
                continue
            }
            // Find the highest priority tag (lowest index in sortedTags)
            var bestTag: String? = nil
            var bestIndex = Int.max
            for tag in nonContextTags {
                if let idx = tagIndex[tag], idx < bestIndex {
                    bestIndex = idx
                    bestTag = tag
                }
            }
            if let tag = bestTag {
                todosByTag[tag, default: []].append(todo)
            }
        }

        // Build groups in sorted order
        var groups: [(tag: String?, todos: [Todo])] = []
        for tag in sortedTags {
            if let todos = todosByTag[tag], !todos.isEmpty {
                groups.append((tag: tag, todos: todos))
            }
        }

        if !untaggedTodos.isEmpty {
            groups.append((tag: nil, todos: untaggedTodos))
        }

        return groups
    }

    // Tag mode view - group by any tag, sorted by frequency
    @ViewBuilder
    private var tagModeView: some View {
        let tagGroups = computeTagGroups()

        ForEach(Array(tagGroups.enumerated()), id: \.offset) { _, group in
            TagGroupSection(
                todoList: todoList,
                tag: group.tag,
                todos: group.todos,
                count: group.todos.count
            )
        }

        // Completed section
        let completedTodos = todoList.todos.filter { $0.isCompleted && matchesSearch($0) }
        if !completedTodos.isEmpty {
            ContextTodoSection(
                todoList: todoList,
                section: .completed,
                todos: completedTodos,
                isTop5: false
            )
        }
    }
}

// Urgency section (Today/Urgent) with context sub-groups inside
struct UrgencySectionWithContextGroups: View {
    @ObservedObject var todoList: TodoList
    let urgencySection: ContextSection
    let todosByContext: [(context: ContextSection, todos: [Todo])]

    var totalCount: Int {
        todosByContext.reduce(0) { $0 + $1.todos.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main urgency header
            HStack(spacing: 10) {
                Image(systemName: urgencySection.icon)
                    .font(.system(size: 14))
                    .foregroundColor(urgencySection.color)

                Text(urgencySection.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(urgencySection.color)

                Text("\(totalCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(urgencySection.color))

                Spacer()

                // Clear Today button (only for Today section)
                if urgencySection.id == "today" {
                    Button(action: { todoList.clearTodayTags() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11))
                            Text("Clear")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(urgencySection.color.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Remove #today tag from all items")
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.vertical, 12)
            .background(urgencySection.color.opacity(0.08))

            Rectangle()
                .fill(urgencySection.color.opacity(0.5))
                .frame(height: 2)

            // Context sub-groups
            VStack(spacing: 0) {
                ForEach(todosByContext, id: \.context.id) { item in
                    ContextSubGroup(
                        todoList: todoList,
                        context: item.context,
                        todos: item.todos,
                        parentColor: urgencySection.color
                    )
                }
            }
        }
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadiusMd)
        .overlay(
            Rectangle()
                .fill(urgencySection.color)
                .frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .stroke(urgencySection.color.opacity(0.15), lineWidth: 1)
        )
        .padding(.vertical, 6)
    }
}

// Context sub-group within an urgency section
struct ContextSubGroup: View {
    @ObservedObject var todoList: TodoList
    let context: ContextSection
    let todos: [Todo]
    let parentColor: Color

    var body: some View {
        // For "other" context, just list todos without a header
        if context.id == "other" {
            LazyVStack(spacing: 0) {
                ForEach(todos) { todo in
                    TodoItemView(todoList: todoList, todo: todo, isTop5: false, groupColor: parentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Sub-group with left color bar for clear identification
                HStack(spacing: 0) {
                    // Left color indicator bar
                    Rectangle()
                        .fill(context.color)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 0) {
                        // Sub-group header
                        HStack(spacing: 6) {
                            Image(systemName: context.icon)
                                .font(.system(size: 11))
                                .foregroundColor(context.color)

                            Text(context.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(context.color)

                            Text("\(todos.count)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(context.color)
                                )

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(context.color.opacity(0.08))

                        // Todos in this context - with context background color (lazy for performance)
                        LazyVStack(spacing: 0) {
                            ForEach(todos) { todo in
                                TodoItemView(todoList: todoList, todo: todo, isTop5: false, groupColor: context.color)
                            }
                        }
                    }
                }
                .background(Theme.cardBackground)
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }
}

// Tag-based section view for tag mode grouping
struct TagGroupSection: View {
    @ObservedObject var todoList: TodoList
    let tag: String?  // nil for untagged
    let todos: [Todo]
    let count: Int

    private var tagColor: Color {
        if let tag = tag {
            return Theme.colorForTag(tag)
        }
        return .gray
    }

    private var displayName: String {
        tag ?? "Untagged"
    }

    private var icon: String {
        if let tag = tag {
            return ContextConfigManager.shared.icon(for: tag)
        }
        return "tray"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Left color bar
                Rectangle()
                    .fill(tagColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(tagColor)

                        Text(displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.text)

                        Text("\(todos.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(tagColor)
                            )

                        Spacer()
                    }
                    .padding(.horizontal, Theme.contentPadding)
                    .padding(.vertical, 12)
                    .background(tagColor.opacity(0.1))

                    // Todo items with unified background color
                    LazyVStack(spacing: 0) {
                        ForEach(todos) { todo in
                            TodoItemView(todoList: todoList, todo: todo, isTop5: false, groupColor: tagColor)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                    .stroke(tagColor.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.vertical, 6)
    }
}

// Context-based section view (replaces TodoListSection)
struct ContextTodoSection: View {
    @ObservedObject var todoList: TodoList
    let section: ContextSection
    let todos: [Todo]
    var isTop5: Bool = false

    var body: some View {
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Section header with colored accent
                HStack(spacing: 10) {
                    Image(systemName: section.icon)
                        .font(.system(size: 14))
                        .foregroundColor(section.color)
                        .frame(width: 16, height: 16)

                    Text(section.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(section.id == "today" || section.id == "urgent" ? section.color : Theme.text)

                    Text("\(todos.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(section.color)
                        )

                    Spacer()

                    if section.id == "completed" {
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

                    // Clear Today button
                    if section.id == "today" {
                        Button(action: { todoList.clearTodayTags() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 11))
                                Text("Clear")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(section.color.opacity(0.8))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Remove #today tag from all items")
                    }
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.vertical, 12)
                .background(
                    section.color.opacity(section.id == "today" || section.id == "urgent" ? 0.1 : 0.06)
                )

                // Colored line under header
                Rectangle()
                    .fill(section.color.opacity(0.5))
                    .frame(height: 2)

                // Todo items - with section background color
                LazyVStack(spacing: 0) {
                    ForEach(todos) { todo in
                        TodoItemView(todoList: todoList, todo: todo, isTop5: isTop5, groupColor: section.color)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadiusMd)
            .overlay(
                Rectangle()
                    .fill(section.color)
                    .frame(width: 3),
                alignment: .leading
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                    .stroke(section.color.opacity(0.15), lineWidth: 1)
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
        .background(Theme.cardBackground)
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