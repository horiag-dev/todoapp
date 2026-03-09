import XCTest
@testable import TodoApp

final class TodoListTests: XCTestCase {
    var todoList: TodoList!

    override func setUp() {
        super.setUp()
        todoList = TodoList()
        // Clear any loaded state for clean tests
        todoList.todos = []
        todoList.top5Todos = []
        todoList.deletedTodos = []
        todoList.bigThings = []
        todoList.goals = ""
    }

    override func tearDown() {
        todoList = nil
        super.tearDown()
    }

    // MARK: - Todo Model Tests

    func testTodoDefaultValues() {
        let todo = Todo(title: "Test")
        XCTAssertEqual(todo.title, "Test")
        XCTAssertFalse(todo.isCompleted)
        XCTAssertTrue(todo.tags.isEmpty)
        XCTAssertEqual(todo.priority, .thisWeek, "Default priority should be .thisWeek")
    }

    func testTodoWithAllParameters() {
        let todo = Todo(title: "Full todo", isCompleted: true, tags: ["work", "deep"], priority: .urgent)
        XCTAssertEqual(todo.title, "Full todo")
        XCTAssertTrue(todo.isCompleted)
        XCTAssertEqual(todo.tags, ["work", "deep"])
        XCTAssertEqual(todo.priority, .urgent)
    }

    func testTodoContainsLinks() {
        let todoWithLink = Todo(title: "Check https://example.com for details")
        XCTAssertTrue(todoWithLink.containsLinks)

        let todoWithoutLink = Todo(title: "Just a regular task")
        XCTAssertFalse(todoWithoutLink.containsLinks)
    }

    func testTodoEquality() {
        let todo1 = Todo(title: "Same")
        var todo2 = todo1
        XCTAssertEqual(todo1, todo2)

        todo2.title = "Different"
        XCTAssertNotEqual(todo1, todo2)
    }

    func testTodoUniqueIds() {
        let todo1 = Todo(title: "First")
        let todo2 = Todo(title: "Second")
        XCTAssertNotEqual(todo1.id, todo2.id)
    }

    // MARK: - Priority Tests

    func testPriorityCaseIterable() {
        let allCases = Priority.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.today))
        XCTAssertTrue(allCases.contains(.thisWeek))
        XCTAssertTrue(allCases.contains(.urgent))
        XCTAssertTrue(allCases.contains(.normal))
    }

    func testPriorityEmoji() {
        XCTAssertEqual(Priority.today.emoji, "☀️")
        XCTAssertEqual(Priority.thisWeek.emoji, "🟠")
        XCTAssertEqual(Priority.urgent.emoji, "🔴")
        XCTAssertEqual(Priority.normal.emoji, "🔵")
    }

    func testPriorityRawValues() {
        XCTAssertEqual(Priority.today.rawValue, "Today")
        XCTAssertEqual(Priority.thisWeek.rawValue, "This Week")
        XCTAssertEqual(Priority.urgent.rawValue, "Urgent")
        XCTAssertEqual(Priority.normal.rawValue, "Normal")
    }

    func testPriorityDecodesLegacyValue() throws {
        // "When there's time" should decode as .normal
        let json = "\"When there's time\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Priority.self, from: data)
        XCTAssertEqual(decoded, .normal)
    }

    func testPriorityDecodesUnknownAsNormal() throws {
        let json = "\"SomeUnknownPriority\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Priority.self, from: data)
        XCTAssertEqual(decoded, .normal)
    }

    // MARK: - Add/Remove Todo Tests

    func testAddTodo() {
        XCTAssertTrue(todoList.todos.isEmpty)

        let todo = Todo(title: "Test todo", priority: .normal)
        todoList.todos.append(todo)

        XCTAssertEqual(todoList.todos.count, 1)
        XCTAssertEqual(todoList.todos.first?.title, "Test todo")
    }

    func testAddTodoViaMethod() {
        todoList.addTodo(title: "Via method", tags: ["work"], priority: .urgent)
        XCTAssertEqual(todoList.todos.count, 1)
        XCTAssertEqual(todoList.todos.first?.title, "Via method")
        XCTAssertEqual(todoList.todos.first?.tags, ["work"])
        XCTAssertEqual(todoList.todos.first?.priority, .urgent)
    }

    func testAddTodoDefaultPriority() {
        todoList.addTodo(title: "Default priority")
        XCTAssertEqual(todoList.todos.first?.priority, .thisWeek)
    }

    func testRemoveTodo() {
        let todo = Todo(title: "To remove")
        todoList.todos.append(todo)
        todoList.todos.removeAll { $0.id == todo.id }
        XCTAssertTrue(todoList.todos.isEmpty)
    }

    // MARK: - Toggle Todo Tests

    func testToggleTodo() {
        let todo = Todo(title: "Toggle me")
        todoList.todos.append(todo)
        XCTAssertFalse(todoList.todos[0].isCompleted)

        todoList.toggleTodo(todo)
        XCTAssertTrue(todoList.todos[0].isCompleted)

        todoList.toggleTodo(todoList.todos[0])
        XCTAssertFalse(todoList.todos[0].isCompleted)
    }

    func testToggleNonexistentTodoDoesNothing() {
        let todo = Todo(title: "Not in list")
        todoList.toggleTodo(todo) // Should not crash
        XCTAssertTrue(todoList.todos.isEmpty)
    }

    // MARK: - Delete/Restore Tests

    func testDeleteTodoMovesToDeleted() {
        let todo = Todo(title: "Delete me")
        todoList.todos.append(todo)

        todoList.deleteTodo(todo)

        XCTAssertTrue(todoList.todos.isEmpty)
        XCTAssertEqual(todoList.deletedTodos.count, 1)
        XCTAssertEqual(todoList.deletedTodos.first?.title, "Delete me")
    }

    func testRestoreTodo() {
        let todo = Todo(title: "Restore me")
        todoList.todos.append(todo)
        todoList.deleteTodo(todo)

        let deletedTodo = todoList.deletedTodos.first!
        todoList.restoreTodo(deletedTodo)

        XCTAssertEqual(todoList.todos.count, 1)
        XCTAssertTrue(todoList.deletedTodos.isEmpty)
    }

    func testPermanentlyDeleteTodo() {
        let todo = Todo(title: "Gone forever")
        todoList.deletedTodos.append(todo)

        todoList.permanentlyDeleteTodo(todo)
        XCTAssertTrue(todoList.deletedTodos.isEmpty)
    }

    func testMoveAllCompletedToDeleted() {
        let completed1 = Todo(title: "Done 1", isCompleted: true)
        let completed2 = Todo(title: "Done 2", isCompleted: true)
        let active = Todo(title: "Still active")
        todoList.todos = [completed1, completed2, active]

        todoList.moveAllCompletedToDeleted()

        XCTAssertEqual(todoList.todos.count, 1)
        XCTAssertEqual(todoList.todos.first?.title, "Still active")
        XCTAssertEqual(todoList.deletedTodos.count, 2)
    }

    // MARK: - Tag Tests

    func testAddTag() {
        let todo = Todo(title: "Tag me")
        todoList.todos.append(todo)

        todoList.addTag(to: todo, tag: "work")

        XCTAssertEqual(todoList.todos[0].tags, ["work"])
    }

    func testAddDuplicateTagIgnored() {
        let todo = Todo(title: "Tag me")
        todoList.todos.append(todo)

        todoList.addTag(to: todo, tag: "work")
        todoList.addTag(to: todoList.todos[0], tag: "work")

        XCTAssertEqual(todoList.todos[0].tags.count, 1)
    }

    func testRemoveTag() {
        let todo = Todo(title: "Untag me", tags: ["work", "deep"])
        todoList.todos.append(todo)

        todoList.removeTag(from: todoList.todos[0], tag: "work")

        XCTAssertEqual(todoList.todos[0].tags, ["deep"])
    }

    func testAllTags() {
        todoList.todos = [
            Todo(title: "A", tags: ["work", "deep"]),
            Todo(title: "B", tags: ["deep", "reply"]),
        ]

        let tags = todoList.allTags
        XCTAssertEqual(tags.count, 3) // deep, reply, work (sorted)
        XCTAssertEqual(tags, ["deep", "reply", "work"])
    }

    func testAllTagsIncludesTop5() {
        todoList.todos = [Todo(title: "A", tags: ["work"])]
        todoList.top5Todos = [Todo(title: "B", tags: ["top5tag"])]

        let tags = todoList.allTags
        XCTAssertTrue(tags.contains("work"))
        XCTAssertTrue(tags.contains("top5tag"))
    }

    func testTodosByTag() {
        todoList.todos = [
            Todo(title: "Work task", tags: ["work"]),
            Todo(title: "Personal task", tags: ["personal"]),
            Todo(title: "Both", tags: ["work", "personal"]),
        ]

        let workTodos = todoList.todosByTag("work")
        XCTAssertEqual(workTodos.count, 2)

        let personalTodos = todoList.todosByTag("personal")
        XCTAssertEqual(personalTodos.count, 2)

        let nonexistent = todoList.todosByTag("nonexistent")
        XCTAssertTrue(nonexistent.isEmpty)
    }

    func testRenameTag() {
        todoList.todos = [
            Todo(title: "A", tags: ["oldtag", "keep"]),
            Todo(title: "B", tags: ["oldtag"]),
            Todo(title: "C", tags: ["other"]),
        ]
        todoList.top5Todos = [
            Todo(title: "Top", tags: ["oldtag"]),
        ]

        todoList.renameTag(from: "oldtag", to: "newtag")

        XCTAssertEqual(todoList.todos[0].tags, ["newtag", "keep"])
        XCTAssertEqual(todoList.todos[1].tags, ["newtag"])
        XCTAssertEqual(todoList.todos[2].tags, ["other"])
        XCTAssertEqual(todoList.top5Todos[0].tags, ["newtag"])
    }

    // MARK: - Update Todo Tests

    func testUpdateTodo() {
        var todo = Todo(title: "Original")
        todoList.todos.append(todo)

        todo.title = "Updated"
        todo.priority = .urgent
        todoList.updateTodo(todo)

        XCTAssertEqual(todoList.todos[0].title, "Updated")
        XCTAssertEqual(todoList.todos[0].priority, .urgent)
    }

    func testUpdateTodoTags() {
        let todo = Todo(title: "Update tags")
        todoList.todos.append(todo)

        todoList.updateTodo(todo, withTags: ["new1", "new2"])

        XCTAssertEqual(todoList.todos[0].tags, ["new1", "new2"])
    }

    func testUpdateNonexistentTodoDoesNothing() {
        let todo = Todo(title: "Not in list")
        todoList.updateTodo(todo) // Should not crash
        XCTAssertTrue(todoList.todos.isEmpty)
    }

    // MARK: - Big Things Tests

    func testAddBigThing() {
        todoList.addBigThing("Ship v2.0")
        XCTAssertEqual(todoList.bigThings, ["Ship v2.0"])
    }

    func testAddEmptyBigThingIgnored() {
        todoList.addBigThing("")
        XCTAssertTrue(todoList.bigThings.isEmpty)
    }

    func testRemoveBigThing() {
        todoList.bigThings = ["First", "Second", "Third"]
        todoList.removeBigThing(at: 1)
        XCTAssertEqual(todoList.bigThings, ["First", "Third"])
    }

    func testRemoveBigThingOutOfBounds() {
        todoList.bigThings = ["Only"]
        todoList.removeBigThing(at: 5) // Should not crash
        todoList.removeBigThing(at: -1) // Should not crash
        XCTAssertEqual(todoList.bigThings.count, 1)
    }

    func testBigThingsMarkdown() {
        todoList.bigThings = ["Ship v2.0", "Hire engineer", "Launch campaign"]
        let md = todoList.bigThingsMarkdown
        XCTAssertTrue(md.contains("1. Ship v2.0"))
        XCTAssertTrue(md.contains("2. Hire engineer"))
        XCTAssertTrue(md.contains("3. Launch campaign"))
    }

    func testBigThingsMarkdownEmpty() {
        todoList.bigThings = []
        XCTAssertEqual(todoList.bigThingsMarkdown, "")
    }

    // MARK: - Top 5 Tests

    func testAddTop5Todo() {
        let todo = Todo(title: "Important")
        todoList.addTop5Todo(todo)
        XCTAssertEqual(todoList.top5Todos.count, 1)
        XCTAssertEqual(todoList.top5Todos.first?.title, "Important")
    }

    func testToggleTop5Todo() {
        let todo = Todo(title: "Top task")
        todoList.top5Todos.append(todo)

        todoList.toggleTop5Todo(todo)
        XCTAssertTrue(todoList.top5Todos[0].isCompleted)
    }

    func testDeleteTop5Todo() {
        let todo = Todo(title: "Remove from top 5")
        todoList.top5Todos.append(todo)

        todoList.deleteTop5Todo(todo)
        XCTAssertTrue(todoList.top5Todos.isEmpty)
    }

    func testMoveTop5TodoUp() {
        let todo1 = Todo(title: "First")
        let todo2 = Todo(title: "Second")
        todoList.top5Todos = [todo1, todo2]

        todoList.moveTop5Todo(todo2, direction: -1)

        XCTAssertEqual(todoList.top5Todos[0].title, "Second")
        XCTAssertEqual(todoList.top5Todos[1].title, "First")
    }

    func testMoveTop5TodoDown() {
        let todo1 = Todo(title: "First")
        let todo2 = Todo(title: "Second")
        todoList.top5Todos = [todo1, todo2]

        todoList.moveTop5Todo(todo1, direction: 1)

        XCTAssertEqual(todoList.top5Todos[0].title, "Second")
        XCTAssertEqual(todoList.top5Todos[1].title, "First")
    }

    func testMoveTop5TodoBeyondBoundsDoesNothing() {
        let todo = Todo(title: "Only one")
        todoList.top5Todos = [todo]

        todoList.moveTop5Todo(todo, direction: -1) // Can't move up
        XCTAssertEqual(todoList.top5Todos.count, 1)

        todoList.moveTop5Todo(todo, direction: 1) // Can't move down
        XCTAssertEqual(todoList.top5Todos.count, 1)
    }

    func testClearTop5() {
        todoList.top5Todos = [Todo(title: "A"), Todo(title: "B")]
        todoList.clearTop5()
        XCTAssertTrue(todoList.top5Todos.isEmpty)
    }

    func testAddTagToTop5Todo() {
        let todo = Todo(title: "Tag top 5")
        todoList.top5Todos.append(todo)

        todoList.addTagToTop5Todo(todo, tag: "important")
        XCTAssertEqual(todoList.top5Todos[0].tags, ["important"])
    }

    func testRemoveTagFromTop5Todo() {
        let todo = Todo(title: "Untag top 5", tags: ["remove", "keep"])
        todoList.top5Todos.append(todo)

        todoList.removeTagFromTop5Todo(todo, tag: "remove")
        XCTAssertEqual(todoList.top5Todos[0].tags, ["keep"])
    }

    // MARK: - Clear Today Tests

    func testClearTodayTags() {
        todoList.todos = [
            Todo(title: "Today task", priority: .today),
            Todo(title: "This week task", priority: .thisWeek),
            Todo(title: "Another today", priority: .today),
        ]

        todoList.clearTodayTags()

        XCTAssertEqual(todoList.todos[0].priority, .thisWeek)
        XCTAssertEqual(todoList.todos[1].priority, .thisWeek)
        XCTAssertEqual(todoList.todos[2].priority, .thisWeek)
    }

    func testClearTodayTagsNoOpWhenNoneExist() {
        todoList.todos = [
            Todo(title: "Normal", priority: .normal),
        ]

        todoList.clearTodayTags() // Should not crash or change anything
        XCTAssertEqual(todoList.todos[0].priority, .normal)
    }
}
