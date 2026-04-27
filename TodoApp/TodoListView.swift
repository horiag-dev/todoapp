import SwiftUI
import AppKit

struct TodoListView: View {
    @ObservedObject var todoList: TodoList
    @State private var newTodoTitle = ""
    @State private var newTodoPriority: Priority = .today
    @State private var leftColumnWidth: CGFloat = 380
    @State private var isInMindMapMode: Bool = false  // Toggle between list and mind map views
    @State private var showingSettings: Bool = false  // Settings sheet
    @State private var selectedTag: String? = nil  // Tag filter
    @State private var searchText: String = ""  // Search filter
    @State private var isSearching: Bool = false  // Show search bar
    @State private var showingWalkthrough: Bool = false  // Walkthrough guide
    @State private var showingWeeklyReview: Bool = false  // AI weekly review

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

                    // Weekly Review button
                    Button(action: {
                        withAnimation(Theme.Animation.quickFade) {
                            showingWeeklyReview = true
                        }
                    }) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(showingWeeklyReview ? Theme.accent : Theme.secondaryText)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .fill(showingWeeklyReview ? Theme.accent.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("AI Weekly Review")

                    // Guide button
                    Button(action: {
                        withAnimation(Theme.Animation.quickFade) {
                            showingWalkthrough = true
                        }
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("App Guide")

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

                // Save error banner
                if let error = todoList.lastSaveError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 11))
                        Spacer()
                        Button("Retry") { todoList.saveTodos() }
                            .font(.system(size: 11, weight: .medium))
                        Button(action: { todoList.lastSaveError = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(6)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }

                // Main Content - Either Mind Map or List View
                if isInMindMapMode {
                    // Mind Map View
                    MindMapView(todoList: todoList)
                        .transition(.opacity)
                } else {
                    // List View with Resizable Columns
                    HStack(spacing: 0) {
                        // Left Column - Goals & Reading List
                        ScrollView {
                            VStack(spacing: 12) {
                                EditableGoalsView(todoList: todoList)
                            }
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
                                TodoListSections(todoList: todoList, excludeTop5: true, searchText: searchText)
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
        .overlay {
            if showingWalkthrough {
                WalkthroughView(isPresented: $showingWalkthrough)
            }
        }
        .overlay {
            if showingWeeklyReview {
                WeeklyReviewView(isPresented: $showingWeeklyReview, todoList: todoList)
            }
        }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "hasSeenWalkthrough") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(Theme.Animation.quickFade) {
                        showingWalkthrough = true
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWalkthrough)) { _ in
            withAnimation(Theme.Animation.quickFade) {
                showingWalkthrough = true
            }
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
            newTodoPriority = .today
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
    @State private var suggestedTag: String? = nil
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
                // Priority label - click to cycle: today -> urgent -> thisWeek -> normal
                Text(newTodoPriority.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(newTodoPriority.color)
                    )
                    .onTapGesture {
                        withAnimation(Theme.Animation.microSpring) {
                            switch newTodoPriority {
                            case .today:
                                newTodoPriority = .urgent
                            case .urgent:
                                newTodoPriority = .thisWeek
                            case .thisWeek:
                                newTodoPriority = .normal
                            case .normal:
                                newTodoPriority = .today
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
                            suggestedTag = nil
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
            if showSuggestions, let tag = suggestedTag {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.purple)

                    Text("Suggested:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.secondaryText)

                    SuggestionChip(
                        tag: tag,
                        isSelected: selectedTags.contains(tag)
                    ) {
                        toggleTag(tag)
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
                                    TagPillView(tag: tag, size: .small)
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
                    suggestedTag = suggestion.suggestedTag
                    // Auto-apply the suggested tag if found
                    if let tag = suggestion.suggestedTag {
                        selectedTags.insert(tag)
                    }
                    showSuggestions = suggestion.suggestedTag != nil
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
            suggestedTag = nil
            showSuggestions = false
            newTodoPriority = .today
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
