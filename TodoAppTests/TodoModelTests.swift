import XCTest
@testable import TodoApp

final class TodoModelTests: XCTestCase {

    // MARK: - Todo Codable Tests

    func testTodoCodableRoundTrip() throws {
        let original = Todo(title: "Codable test", isCompleted: true, tags: ["work", "deep"], priority: .urgent)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Todo.self, from: data)

        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.isCompleted, original.isCompleted)
        XCTAssertEqual(decoded.tags, original.tags)
        XCTAssertEqual(decoded.priority, original.priority)
    }

    func testPriorityCodableRoundTrip() throws {
        for priority in Priority.allCases {
            let data = try JSONEncoder().encode(priority)
            let decoded = try JSONDecoder().decode(Priority.self, from: data)
            XCTAssertEqual(decoded, priority, "Priority \(priority.rawValue) should survive encoding/decoding")
        }
    }

    // MARK: - Link Detection Tests

    func testContainsHttpsLink() {
        let todo = Todo(title: "Visit https://apple.com today")
        XCTAssertTrue(todo.containsLinks)
    }

    func testContainsHttpLink() {
        let todo = Todo(title: "Check http://example.com")
        XCTAssertTrue(todo.containsLinks)
    }

    func testNoLinksInPlainText() {
        let todo = Todo(title: "Just a normal task without URLs")
        XCTAssertFalse(todo.containsLinks)
    }

    func testHashtagIsNotALink() {
        let todo = Todo(title: "Task with #hashtag")
        XCTAssertFalse(todo.containsLinks)
    }

    // MARK: - Static Content Tests

    func testBlankFileContentHasSections() {
        let content = TodoList.blankFileContent()
        XCTAssertTrue(content.contains("# Goals"))
        XCTAssertTrue(content.contains("☀️ Today"))
        XCTAssertTrue(content.contains("🟠 This Week"))
        XCTAssertTrue(content.contains("⚪ Normal"))
        XCTAssertTrue(content.contains("✅ Completed"))
        XCTAssertTrue(content.contains("🗑️ Deleted"))
    }

    func testDemoFileContentHasSections() {
        let content = TodoList.demoFileContent()
        XCTAssertTrue(content.contains("🎯 Goals"))
        XCTAssertTrue(content.contains("Top 5 of the week"))
        XCTAssertTrue(content.contains("📋 Big Things"))
        XCTAssertTrue(content.contains("☀️ Today"))
        XCTAssertTrue(content.contains("🟠 This Week"))
    }

    func testDemoFileContentHasTodos() {
        let content = TodoList.demoFileContent()
        XCTAssertTrue(content.contains("- [ ]"), "Demo file should contain uncompleted todos")
        XCTAssertTrue(content.contains("- [x]"), "Demo file should contain completed todos")
        XCTAssertTrue(content.contains("#"), "Demo file should contain tags")
    }

    func testDemoFileContentHasGoals() {
        let content = TodoList.demoFileContent()
        XCTAssertTrue(content.contains("#launch"))
        XCTAssertTrue(content.contains("#growth"))
        XCTAssertTrue(content.contains("#team"))
    }
}
