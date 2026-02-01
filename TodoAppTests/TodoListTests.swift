import XCTest
@testable import TodoApp

final class TodoListTests: XCTestCase {
    var todoList: TodoList!
    
    override func setUp() {
        super.setUp()
        todoList = TodoList()
    }
    
    override func tearDown() {
        todoList = nil
        super.tearDown()
    }
    
    func testAddAndRemoveTag() {
        // Test adding a tag
        let todo = Todo(title: "Test todo", priority: .normal)
        todoList.todos.append(todo)
        
        XCTAssertTrue(todoList.allTags.isEmpty, "Tags should be empty initially")
        
        todoList.addTag("test", to: todo)
        XCTAssertEqual(todoList.allTags.count, 1, "Should have one tag")
        XCTAssertTrue(todoList.allTags.contains("test"), "Should contain 'test' tag")
        XCTAssertTrue(todo.tags.contains("test"), "Todo should have 'test' tag")
        
        // Test removing a tag
        todoList.removeTag("test", from: todo)
        XCTAssertTrue(todoList.allTags.isEmpty, "Tags should be empty after removal")
        XCTAssertTrue(todo.tags.isEmpty, "Todo should have no tags")
    }
    
    func testAddAndRemoveTodo() {
        XCTAssertTrue(todoList.todos.isEmpty, "Todos should be empty initially")
        
        // Test adding a todo
        let todo = Todo(title: "Test todo", priority: .normal)
        todoList.todos.append(todo)
        XCTAssertEqual(todoList.todos.count, 1, "Should have one todo")
        XCTAssertEqual(todoList.todos.first?.title, "Test todo", "Todo title should match")
        
        // Test removing a todo
        todoList.todos.removeAll { $0.id == todo.id }
        XCTAssertTrue(todoList.todos.isEmpty, "Todos should be empty after removal")
    }
    
    func testTodoWithMultipleTags() {
        let todo = Todo(title: "Multi-tag todo", priority: .urgent)
        todoList.todos.append(todo)
        
        // Add multiple tags
        todoList.addTag("work", to: todo)
        todoList.addTag("important", to: todo)
        todoList.addTag("project", to: todo)
        
        XCTAssertEqual(todoList.allTags.count, 3, "Should have three tags")
        XCTAssertEqual(todo.tags.count, 3, "Todo should have three tags")
        
        // Remove one tag
        todoList.removeTag("important", from: todo)
        XCTAssertEqual(todoList.allTags.count, 2, "Should have two tags")
        XCTAssertEqual(todo.tags.count, 2, "Todo should have two tags")
        XCTAssertFalse(todo.tags.contains("important"), "Todo should not contain 'important' tag")
    }
    
    func testTodoProperties() {
        let todo = Todo(title: "Test properties", priority: .normal)
        todoList.todos.append(todo)
        
        // Test completion status
        XCTAssertFalse(todo.isCompleted, "Todo should not be completed initially")
        todo.isCompleted = true
        XCTAssertTrue(todo.isCompleted, "Todo should be completed")
        
        // Test priority (default is now thisWeek)
        XCTAssertEqual(todo.priority, .thisWeek, "Todo should have thisWeek priority by default")
        todo.priority = .urgent
        XCTAssertEqual(todo.priority, .urgent, "Todo should have urgent priority")
        
        // Test title
        XCTAssertEqual(todo.title, "Test properties", "Todo title should match")
    }
} 