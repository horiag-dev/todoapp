import Foundation
import SwiftUI
import UniformTypeIdentifiers

class TodoList: ObservableObject {
    @Published var todos: [Todo] = []
    @Published var deletedTodos: [Todo] = []
    @Published var bigThings: [String] = []
    @Published var goals: String = ""
    @Published var selectedFile: URL? {
        didSet {
            if let file = selectedFile {
                UserDefaults.standard.set(file.path, forKey: "lastUsedFile")
            }
        }
    }
    @Published var isDeletedSectionCollapsed = true
    @Published var todosFileURL: URL?
    
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
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
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
        openPanel.allowedContentTypes = [UTType(filenameExtension: "md")!]
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
        savePanel.allowedContentTypes = [UTType(filenameExtension: "md")!]
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
    
    func addTodo(title: String, tags: [String] = [], priority: Priority = .normal) {
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
        
        // Save changes
        saveTodos()
    }
    
    var allTags: [String] {
        let tags = todos.flatMap { $0.tags }
        return Array(Set(tags)).sorted()
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
    
    func addBigThing(_ thing: String) {
        if !thing.isEmpty {
            bigThings.append(thing)
            saveTodos()
        }
    }
    
    func removeBigThing(at index: Int) {
        bigThings.remove(at: index)
        saveTodos()
    }
    
    func saveTodos() {
        guard let fileURL = todosFileURL else {
            print("No file selected")
            return
        }
        
        var markdownContent = "# Todo List\n\n"
        
        // Add goals notepad
        if !goals.isEmpty {
            markdownContent += "## 🎯 Goals\n\n"
            markdownContent += goals
            markdownContent += "\n\n"
        }
        
        // Add big things of the week
        if !bigThings.isEmpty {
            markdownContent += "## 📋 Big Things for the Week\n\n"
            for (index, thing) in bigThings.enumerated() {
                markdownContent += "\(index + 1). \(thing)\n"
            }
            markdownContent += "\n"
        }
        
        // Group todos by priority
        let urgentTodos = todos.filter { $0.priority == .urgent && !$0.isCompleted }
        let normalTodos = todos.filter { $0.priority == .normal && !$0.isCompleted }
        let lowPriorityTodos = todos.filter { $0.priority == .whenTime && !$0.isCompleted }
        let completedTodos = todos.filter { $0.isCompleted }
        
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
        
        // Add low priority todos
        if !lowPriorityTodos.isEmpty {
            markdownContent += "### ⚪ When there's time\n\n"
            for todo in lowPriorityTodos {
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
            print("No file selected")
            return
        }
        
        do {
            let markdownContent = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = markdownContent.components(separatedBy: .newlines)
            
            var currentPriority: Priority = .normal
            var newTodos: [Todo] = []
            var newDeletedTodos: [Todo] = []
            var newBigThings: [String] = []
            var newGoals: [String] = []
            var isInGoalsSection = false
            var isInDeletedSection = false
            var isInBigThingsSection = false
            
            for line in lines {
                if line.hasPrefix("## ") {
                    let sectionName = line.replacingOccurrences(of: "## ", with: "").trimmingCharacters(in: .whitespaces)
                    if sectionName.contains("🎯") {
                        isInGoalsSection = true
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("📋") {
                        isInGoalsSection = false
                        isInDeletedSection = false
                        isInBigThingsSection = true
                    } else {
                        isInGoalsSection = false
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    }
                } else if line.hasPrefix("### ") {
                    let sectionName = line.replacingOccurrences(of: "### ", with: "").trimmingCharacters(in: .whitespaces)
                    if sectionName.contains("🔴") {
                        currentPriority = .urgent
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("🔵") {
                        currentPriority = .normal
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("⚪") {
                        currentPriority = .whenTime
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("✅") {
                        currentPriority = .normal
                        isInDeletedSection = false
                        isInBigThingsSection = false
                    } else if sectionName.contains("🗑️") {
                        isInDeletedSection = true
                        isInBigThingsSection = false
                    }
                }
                
                if isInGoalsSection && !line.isEmpty && !line.hasPrefix("##") {
                    newGoals.append(line)
                } else if line.hasPrefix("- [") {
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
                } else if isInBigThingsSection && line.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                    if let thing = line.split(separator: ".", maxSplits: 1).last {
                        newBigThings.append(thing.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
            
            todos = newTodos
            deletedTodos = newDeletedTodos
            bigThings = newBigThings
            goals = newGoals.joined(separator: "\n")
        } catch {
            print("Error loading todos: \(error)")
            todos = []
            deletedTodos = []
            bigThings = []
            goals = ""
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
                    }
                },
                label: {
                    HStack {
                        Image(systemName: "trash")
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
