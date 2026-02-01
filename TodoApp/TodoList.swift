import Foundation
import SwiftUI
import UniformTypeIdentifiers

class TodoList: ObservableObject {
    @Published var todos: [Todo] = []
    @Published var deletedTodos: [Todo] = []
    @Published var bigThings: [String] = []
    @Published var goals: String = ""
    @Published var quotes: [String] = [] // Motivational quotes
    @Published var selectedFile: URL? {
        didSet {
            if let file = selectedFile {
                UserDefaults.standard.set(file.path, forKey: "lastUsedFile")
            }
        }
    }
    @Published var isDeletedSectionCollapsed = true
    @Published var todosFileURL: URL?
    @Published var top5Todos: [Todo] = [] // Top 5 of the week todos

    private var backupTimer: Timer?
    private let backupInterval: TimeInterval = 10800 // 3 hours in seconds

    // Debounce save operations to reduce disk I/O
    private var saveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.5

    // Cached computed properties for performance
    private var _cachedAllTags: [String]?
    private var _cachedMindMapNodes: [MindMapNode]?
    private var _todoTagsHash: Int = 0  // Track changes to invalidate cache

    
    var bigThingsMarkdown: String {
        var markdown = ""
        if !bigThings.isEmpty {
            for (index, thing) in bigThings.enumerated() {
                markdown += "\(index + 1). \(thing)\n"
            }
        }
        return markdown
    }
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    
    init() {
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access documents directory")
        }
        documentsDirectory = docsDir
        
        // Try to load the last used file path
        if let lastPath = UserDefaults.standard.string(forKey: "lastTodoFilePath") {
            todosFileURL = URL(fileURLWithPath: lastPath)
            selectedFile = URL(fileURLWithPath: lastPath)
            loadTodos()
        } else {
            // If no file was previously selected, show the file picker
            DispatchQueue.main.async {
                self.showInitialFilePicker()
            }
        }
        
        loadLastUsedFile()
    }
    
    private func loadLastUsedFile() {
        if let filePath = UserDefaults.standard.string(forKey: "lastUsedFile") {
            selectedFile = URL(fileURLWithPath: filePath)
        }
    }
    
    func showInitialFilePicker() {
        let alert = NSAlert()
        alert.messageText = "Welcome to Todo App"
        alert.informativeText = "Would you like to open an existing todo file or create a new one?"
        alert.addButton(withTitle: "Open Existing File")
        alert.addButton(withTitle: "Create New File")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            showOpenPanel()
        case .alertSecondButtonReturn:
            showSavePanel()
        default:
            break
        }
    }
    
    func showOpenPanel() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Open Todo File"
        openPanel.message = "Select an existing .md file"
        openPanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                self.selectFile(url)
            }
        }
    }
    
    func showSavePanel() {
        let savePanel = NSSavePanel()
        savePanel.title = "Create New Todo File"
        savePanel.message = "Choose where to save your todo list"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        savePanel.nameFieldStringValue = "todos.md"
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                // Create an empty markdown file
                try? "# Todo List\n\n".write(to: url, atomically: true, encoding: .utf8)
                self.selectFile(url)
            }
        }
    }
    
    func selectFile(_ url: URL) {
        todosFileURL = url
        UserDefaults.standard.set(url.path, forKey: "lastTodoFilePath")
        loadTodos()
        
        // Initialize backup after selecting a file
        setupBackupTimer()
    }
    
    func createNewFile() {
        showSavePanel()
    }
    
    func openFile() {
        showOpenPanel()
    }
    
    func addTodo(_ todo: Todo) {
        todos.append(todo)
        saveTodos()
    }
    
    func addTodo(title: String, tags: [String] = [], priority: Priority = .thisWeek) {
        let todo = Todo(title: title, tags: tags, priority: priority)
        todos.append(todo)
        saveTodos()
    }
    
    func toggleTodo(_ todo: Todo) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index].isCompleted.toggle()
            saveTodos()
        }
    }
    
    func deleteTodo(_ todo: Todo) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            let deletedTodo = todos[index]
            deletedTodos.append(deletedTodo)
            todos.remove(at: index)
            saveTodos()
        }
    }
    
    func restoreTodo(_ todo: Todo) {
        if let index = deletedTodos.firstIndex(where: { $0.id == todo.id }) {
            let restoredTodo = deletedTodos[index]
            todos.append(restoredTodo)
            deletedTodos.remove(at: index)
            saveTodos()
        }
    }
    
    func permanentlyDeleteTodo(_ todo: Todo) {
        deletedTodos.removeAll { $0.id == todo.id }
        saveTodos()
    }
    
    func moveAllCompletedToDeleted() {
        let completed = todos.filter { $0.isCompleted }
        deletedTodos.append(contentsOf: completed)
        todos.removeAll { $0.isCompleted }
        saveTodos()
    }
    
    func updateTodo(_ updatedTodo: Todo) {
        if let index = todos.firstIndex(where: { $0.id == updatedTodo.id }) {
            todos[index] = updatedTodo
            saveTodos()
        }
    }
    
    func updateTodo(_ todo: Todo, withTags tags: [String]) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index].tags = tags
            saveTodos()
        }
    }
    
    func renameTag(from oldTag: String, to newTag: String) {
        // Update the tag in all todos
        for i in 0..<todos.count {
            if let index = todos[i].tags.firstIndex(of: oldTag) {
                todos[i].tags[index] = newTag
            }
        }

        // Update in top5Todos as well
        for i in 0..<top5Todos.count {
            if let index = top5Todos[i].tags.firstIndex(of: oldTag) {
                top5Todos[i].tags[index] = newTag
            }
        }

        // Save changes
        saveTodos()
    }
    
    var allTags: [String] {
        let currentHash = computeTagsHash()
        if let cached = _cachedAllTags, currentHash == _todoTagsHash {
            return cached
        }
        let tags = todos.flatMap { $0.tags } + top5Todos.flatMap { $0.tags }
        let result = Array(Set(tags)).sorted()
        _cachedAllTags = result
        _todoTagsHash = currentHash
        return result
    }

    /// Builds the mind map tree from goals and todos (cached)
    var mindMapNodes: [MindMapNode] {
        let currentHash = computeTagsHash()
        if let cached = _cachedMindMapNodes, currentHash == _todoTagsHash {
            return cached
        }
        let result = MindMapDataBuilder.buildMindMapTree(goals: goals, todos: todos, top5Todos: top5Todos)
        _cachedMindMapNodes = result
        return result
    }

    /// Compute a hash to detect changes in todos/tags
    private func computeTagsHash() -> Int {
        var hasher = Hasher()
        hasher.combine(todos.count)
        hasher.combine(top5Todos.count)
        hasher.combine(goals.hashValue)
        for todo in todos {
            hasher.combine(todo.id)
            hasher.combine(todo.tags)
            hasher.combine(todo.isCompleted)
        }
        for todo in top5Todos {
            hasher.combine(todo.id)
            hasher.combine(todo.tags)
        }
        return hasher.finalize()
    }

    /// Invalidate caches when data changes
    private func invalidateCaches() {
        _cachedAllTags = nil
        _cachedMindMapNodes = nil
    }
    
    func todosByTag(_ tag: String) -> [Todo] {
        todos.filter { $0.tags.contains(tag) }
    }
    
    func addTag(to todo: Todo, tag: String) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            if !todos[index].tags.contains(tag) {
                todos[index].tags.append(tag)
                saveTodos()
            }
        }
    }
    
    func removeTag(from todo: Todo, tag: String) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index].tags.removeAll { $0 == tag }
            saveTodos()
        }
    }

    /// Removes the #today tag from all todos that have it
    func clearTodayTags() {
        var changed = false
        for i in 0..<todos.count {
            if let tagIndex = todos[i].tags.firstIndex(where: { $0.lowercased() == "today" }) {
                todos[i].tags.remove(at: tagIndex)
                changed = true
            }
        }
        // Also clear from top5Todos
        for i in 0..<top5Todos.count {
            if let tagIndex = top5Todos[i].tags.firstIndex(where: { $0.lowercased() == "today" }) {
                top5Todos[i].tags.remove(at: tagIndex)
                changed = true
            }
        }
        if changed {
            saveTodos()
        }
    }

    func addBigThing(_ thing: String) {
        if !thing.isEmpty {
            bigThings.append(thing)
            saveTodos()
        }
    }
    
    func removeBigThing(at index: Int) {
        guard index >= 0 && index < bigThings.count else { return }
        bigThings.remove(at: index)
        saveTodos()
    }
    
    func saveTodos() {
        // Cancel any pending save operation
        saveWorkItem?.cancel()

        // Capture current state for background save
        let currentTodos = todos
        let currentTop5Todos = top5Todos
        let currentDeletedTodos = deletedTodos
        let currentBigThings = bigThings
        let currentGoals = goals
        let currentQuotes = quotes
        let fileURL = todosFileURL

        // Create a new debounced save operation
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSave(
                todos: currentTodos,
                top5Todos: currentTop5Todos,
                deletedTodos: currentDeletedTodos,
                bigThings: currentBigThings,
                goals: currentGoals,
                quotes: currentQuotes,
                fileURL: fileURL
            )
        }
        saveWorkItem = workItem

        // Schedule the save on a background queue after the debounce interval
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval) {
            DispatchQueue.global(qos: .utility).async(execute: workItem)
        }
    }

    private func performSave(
        todos: [Todo],
        top5Todos: [Todo],
        deletedTodos: [Todo],
        bigThings: [String],
        goals: String,
        quotes: [String],
        fileURL: URL?
    ) {
        guard let fileURL = fileURL else {
            return
        }

        var markdownContent = "# Todo List\n\n"

        // Add goals notepad
        if !goals.isEmpty {
            markdownContent += "## 🎯 Goals\n\n"
            markdownContent += goals
            markdownContent += "\n\n"
        }

        // Add quotes section
        if !quotes.isEmpty {
            markdownContent += "## 💭 Quotes\n\n"
            for quote in quotes {
                // Handle multi-line quotes - prefix each line with >
                let lines = quote.components(separatedBy: "\n")
                for line in lines {
                    markdownContent += "> \(line)\n"
                }
                markdownContent += "\n"
            }
        }

        // Add Top 5 of the week section
        if !top5Todos.isEmpty {
            markdownContent += "### 🔴 Top 5 of the week\n\n"
            for todo in top5Todos {
                markdownContent += formatTodo(todo)
            }
            markdownContent += "\n"
        }

        // Add big things of the week
        if !bigThings.isEmpty {
            markdownContent += "## 📋 Big Things for the Week\n\n"
            for (index, thing) in bigThings.enumerated() {
                markdownContent += "\(index + 1). \(thing)\n"
            }
            markdownContent += "\n"
        }

        // Group todos by priority in a single pass
        var thisWeekTodos: [Todo] = []
        var urgentTodos: [Todo] = []
        var normalTodos: [Todo] = []
        var completedTodos: [Todo] = []

        for todo in todos {
            if todo.isCompleted {
                completedTodos.append(todo)
            } else {
                switch todo.priority {
                case .thisWeek:
                    thisWeekTodos.append(todo)
                case .urgent:
                    urgentTodos.append(todo)
                case .normal:
                    normalTodos.append(todo)
                }
            }
        }

        // Add this week todos (highest priority after Top 5)
        if !thisWeekTodos.isEmpty {
            markdownContent += "### 🟠 This Week\n\n"
            for todo in thisWeekTodos {
                markdownContent += formatTodo(todo)
            }
            markdownContent += "\n"
        }

        // Add urgent todos
        if !urgentTodos.isEmpty {
            markdownContent += "### 🔴 Urgent\n\n"
            for todo in urgentTodos {
                markdownContent += formatTodo(todo)
            }
            markdownContent += "\n"
        }

        // Add normal todos
        if !normalTodos.isEmpty {
            markdownContent += "### 🔵 Normal\n\n"
            for todo in normalTodos {
                markdownContent += formatTodo(todo)
            }
            markdownContent += "\n"
        }

        // Add completed todos
        if !completedTodos.isEmpty {
            markdownContent += "### ✅ Completed\n\n"
            for todo in completedTodos {
                markdownContent += formatTodo(todo)
            }
            markdownContent += "\n"
        }

        // Add deleted todos
        if !deletedTodos.isEmpty {
            markdownContent += "### 🗑️ Deleted\n\n"
            for todo in deletedTodos {
                markdownContent += formatTodo(todo)
            }
        }

        do {
            try markdownContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving todos: \(error)")
        }
    }
    
    private func formatTodo(_ todo: Todo) -> String {
        var todoString = "- [\(todo.isCompleted ? "x" : " ")] \(todo.title)"
        
        if !todo.tags.isEmpty {
            todoString += " \(todo.tags.map { "#\($0)" }.joined(separator: " "))"
        }
        
        return todoString + "\n"
    }
    
    private func loadTodos() {
        guard let fileURL = todosFileURL else {
            print("❌ No file selected for loading todos")
            return
        }
        
        
        do {
            let markdownContent = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = markdownContent.components(separatedBy: .newlines)
            
            var currentPriority: Priority = .normal
            var newTodos: [Todo] = []
            var newTop5Todos: [Todo] = []
            var newDeletedTodos: [Todo] = []
            var newBigThings: [String] = []
            var newGoals: [String] = []
            var newQuotes: [String] = []
            var isInGoalsSection = false
            var isInQuotesSection = false
            var isInDeletedSection = false
            var isInBigThingsSection = false
            var isInTop5Section = false
            
            for line in lines {
                if line.hasPrefix("## ") {
                    let sectionName = line.replacingOccurrences(of: "## ", with: "").trimmingCharacters(in: .whitespaces)
                    if sectionName.contains("🎯") {
                        isInGoalsSection = true
                        isInQuotesSection = false
                        isInDeletedSection = false
                        isInBigThingsSection = false
                        isInTop5Section = false
                    } else if sectionName.contains("💭") {
                        isInGoalsSection = false
                        isInQuotesSection = true
                        isInDeletedSection = false
                        isInBigThingsSection = false
                        isInTop5Section = false
                    } else if sectionName.contains("📋") {
                        isInGoalsSection = false
                        isInQuotesSection = false
                        isInDeletedSection = false
                        isInBigThingsSection = true
                        isInTop5Section = false
                    } else {
                        isInGoalsSection = false
                        isInQuotesSection = false
                        isInDeletedSection = false
                        isInBigThingsSection = false
                        isInTop5Section = false
                    }
                } else if line.hasPrefix("### ") {
                    // Always reset all section flags on new ### section
                    isInGoalsSection = false
                    isInQuotesSection = false
                    isInBigThingsSection = false
                    isInTop5Section = false
                    isInDeletedSection = false
                    let sectionName = line.replacingOccurrences(of: "### ", with: "").trimmingCharacters(in: .whitespaces)
                    let trimmedSection = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedSection.localizedCaseInsensitiveContains("Top 5 of the week") &&
                        (trimmedSection.contains("🔴") || trimmedSection.contains("🗓️")) {
                        isInTop5Section = true
                        isInDeletedSection = false
                        currentPriority = .normal // Not used for top5
                    } else if sectionName.contains("🟠") || sectionName.localizedCaseInsensitiveContains("This Week") {
                        // This Week section (new priority level)
                        currentPriority = .thisWeek
                        isInTop5Section = false
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("🔴") {
                        currentPriority = .urgent
                        isInTop5Section = false
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("🔵") {
                        currentPriority = .normal
                        isInTop5Section = false
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("⚪") {
                        // Migration: treat "When there's time" as normal
                        currentPriority = .normal
                        isInTop5Section = false
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("✅") {
                        currentPriority = .normal
                        isInTop5Section = false
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("🗑️") {
                        isInDeletedSection = true
                        isInTop5Section = false
                        isInBigThingsSection = false
                    } else {
                        isInTop5Section = false
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    }
                } else if isInGoalsSection && !line.isEmpty && !line.hasPrefix("##") {
                    newGoals.append(line)
                } else if isInQuotesSection && line.hasPrefix(">") {
                    // Parse blockquote format: > quote text
                    let quoteText = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                    // Append to last quote if exists, otherwise create new
                    if let lastIndex = newQuotes.indices.last, !newQuotes[lastIndex].isEmpty {
                        newQuotes[lastIndex] += "\n" + quoteText
                    } else if newQuotes.isEmpty {
                        newQuotes.append(quoteText)
                    } else {
                        newQuotes[newQuotes.count - 1] = quoteText
                    }
                } else if isInQuotesSection && line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Blank line in quotes section = start new quote
                    if let last = newQuotes.last, !last.isEmpty {
                        newQuotes.append("")
                    }
                } else if isInTop5Section && line.hasPrefix("- [") {
                    let components = line.components(separatedBy: "] ")
                    guard components.count >= 2 else { continue }
                    
                    let isCompleted = components[0].contains("x")
                    let rest = components[1]
                    
                    // Split title and tags
                    let parts = rest.components(separatedBy: " #")
                    let title = parts[0]
                    let tags = parts.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
                    
                    let todo = Todo(title: title, isCompleted: isCompleted, tags: tags, priority: .normal) // priority not used
                    newTop5Todos.append(todo)
                } else if isInBigThingsSection && line.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                    if let thing = line.split(separator: ".", maxSplits: 1).last {
                        newBigThings.append(thing.trimmingCharacters(in: .whitespaces))
                    }
                } else if !isInGoalsSection && !isInTop5Section && !isInBigThingsSection && line.hasPrefix("- [") {
                    let components = line.components(separatedBy: "] ")
                    guard components.count >= 2 else { continue }
                    
                    let isCompleted = components[0].contains("x")
                    let rest = components[1]
                    
                    // Split title and tags
                    let parts = rest.components(separatedBy: " #")
                    let title = parts[0]
                    let tags = parts.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
                    
                    let todo = Todo(title: title, isCompleted: isCompleted, tags: tags, priority: currentPriority)
                    
                    if isInDeletedSection {
                        newDeletedTodos.append(todo)
                    } else {
                        newTodos.append(todo)
                    }
                }
            }
            
            todos = newTodos
            top5Todos = newTop5Todos
            deletedTodos = newDeletedTodos
            bigThings = newBigThings
            goals = newGoals.joined(separator: "\n")
            quotes = newQuotes.filter { !$0.isEmpty }
            
            
            // Create initial backup after loading
            DispatchQueue.main.async {
                self.createBackup()
                self.setupBackupTimer()
            }
        } catch {
            print("❌ Error loading todos: \(error)")
            todos = []
            top5Todos = []
            deletedTodos = []
            bigThings = []
            goals = ""
            quotes = []
        }
    }
    
    private func setupBackupTimer() {
        backupTimer = Timer.scheduledTimer(withTimeInterval: backupInterval, repeats: true) { [weak self] _ in
            self?.createBackup()
        }
    }
    
    private func createBackup() {
        guard let fileURL = todosFileURL else {
            print("❌ No file selected for backup")
            return
        }
        
        
        // Use the app's documents directory for backups instead of the original file's directory
        let backupsFolderPath = documentsDirectory.appendingPathComponent("TodoAppBackups")
        
        
        do {
            // Create backups directory if it doesn't exist
            try fileManager.createDirectory(at: backupsFolderPath, withIntermediateDirectories: true, attributes: nil)
            
            // Create and save the backup
            try createBackupFile(at: backupsFolderPath, originalFile: fileURL)
        } catch {
            print("❌ Error creating backup: \(error)")
        }
    }
    
    private func createBackupFile(at folderPath: URL, originalFile: URL) throws {
        // Create timestamp for filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        // Create backup file name based on original file name
        let originalFileName = originalFile.deletingPathExtension().lastPathComponent
        let backupFileName = "\(originalFileName)_backup_\(timestamp).md"
        let backupFilePath = folderPath.appendingPathComponent(backupFileName)
        
        // Copy the original file to the backup location
        try FileManager.default.copyItem(at: originalFile, to: backupFilePath)
    }
    
    deinit {
        backupTimer?.invalidate()
    }
    
    // --- Top 5 of the week methods ---
    func addTop5Todo(_ todo: Todo) {
        top5Todos.append(todo)
        saveTodos()
    }
    func updateTop5Todo(_ updatedTodo: Todo) {
        if let index = top5Todos.firstIndex(where: { $0.id == updatedTodo.id }) {
            top5Todos[index] = updatedTodo
            saveTodos()
        }
    }
    func toggleTop5Todo(_ todo: Todo) {
        if let index = top5Todos.firstIndex(where: { $0.id == todo.id }) {
            top5Todos[index].isCompleted.toggle()
            saveTodos()
        }
    }
    func deleteTop5Todo(_ todo: Todo) {
        top5Todos.removeAll { $0.id == todo.id }
        saveTodos()
    }
    func addTagToTop5Todo(_ todo: Todo, tag: String) {
        if let index = top5Todos.firstIndex(where: { $0.id == todo.id }) {
            if !top5Todos[index].tags.contains(tag) {
                top5Todos[index].tags.append(tag)
                saveTodos()
            }
        }
    }
    func removeTagFromTop5Todo(_ todo: Todo, tag: String) {
        if let index = top5Todos.firstIndex(where: { $0.id == todo.id }) {
            top5Todos[index].tags.removeAll { $0 == tag }
            saveTodos()
        }
    }
    
}

struct DeletedTodosView: View {
    @ObservedObject var todoList: TodoList
    
    var body: some View {
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
                    }
                },
                label: {
                    HStack {
                        Text("Deleted Items")
                        Text("(\(todoList.deletedTodos.count))")
                            .foregroundColor(.secondary)
                    }
                }
            )
            .padding(.horizontal)
        }
    }
} 
