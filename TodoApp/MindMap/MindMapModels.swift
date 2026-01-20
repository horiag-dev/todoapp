import SwiftUI

// MARK: - Node Type
enum MindMapNodeType {
    case goalSection    // Node created from a goal section with #tag
    case orphanTag      // Node for tags that exist in todos but not in goals
}

// MARK: - Mind Map Root Node
struct MindMapNode: Identifiable {
    let id: UUID                        // Deterministic based on tag
    let tag: String                     // The tag driving this node (e.g., "people")
    let title: String                   // Clean title without #tag (e.g., "People Management")
    let nodeType: MindMapNodeType
    var children: [MindMapChildNode]    // Todos with this tag
    var goalItems: [MindMapGoalItem]    // Goal section items (expandable separately)
    var position: CGPoint = .zero       // Calculated by layout engine
    var color: Color                    // From Theme.colorForTag()

    init(tag: String, title: String, nodeType: MindMapNodeType, children: [MindMapChildNode] = [], goalItems: [MindMapGoalItem] = []) {
        // Create deterministic ID from tag hash so it persists across rebuilds
        self.id = Self.deterministicUUID(from: "mindmap-node-\(tag)")
        self.tag = tag
        self.title = title
        self.nodeType = nodeType
        self.children = children
        self.goalItems = goalItems
        self.color = Theme.colorForTag(tag)
    }

    /// Creates a deterministic UUID from a string using its hash
    private static func deterministicUUID(from string: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(string)
        let hash1 = hasher.finalize()

        var hasher2 = Hasher()
        hasher2.combine(string)
        hasher2.combine("salt")
        let hash2 = hasher2.finalize()

        let uuidString = String(format: "%08x-%04x-%04x-%04x-%012x",
                                UInt32(truncatingIfNeeded: hash1),
                                UInt16(truncatingIfNeeded: hash1 >> 32),
                                UInt16(truncatingIfNeeded: hash1 >> 48),
                                UInt16(truncatingIfNeeded: hash2),
                                UInt64(truncatingIfNeeded: hash2) & 0xFFFFFFFFFFFF)
        return UUID(uuidString: uuidString) ?? UUID()
    }
}

// MARK: - Mind Map Goal Item (from goal section bullets)
struct MindMapGoalItem: Identifiable {
    let id: UUID
    let title: String
    var position: CGPoint = .zero

    init(title: String, parentTag: String, index: Int) {
        // Deterministic ID based on parent tag and index
        self.id = Self.deterministicUUID(from: "goal-item-\(parentTag)-\(index)")
        self.title = title
    }

    private static func deterministicUUID(from string: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(string)
        let hash1 = hasher.finalize()

        var hasher2 = Hasher()
        hasher2.combine(string)
        hasher2.combine("salt")
        let hash2 = hasher2.finalize()

        let uuidString = String(format: "%08x-%04x-%04x-%04x-%012x",
                                UInt32(truncatingIfNeeded: hash1),
                                UInt16(truncatingIfNeeded: hash1 >> 32),
                                UInt16(truncatingIfNeeded: hash1 >> 48),
                                UInt16(truncatingIfNeeded: hash2),
                                UInt64(truncatingIfNeeded: hash2) & 0xFFFFFFFFFFFF)
        return UUID(uuidString: uuidString) ?? UUID()
    }
}

// MARK: - Mind Map Child Node (Todo)
struct MindMapChildNode: Identifiable {
    let id: UUID                        // From Todo.id
    let title: String
    let isCompleted: Bool
    let priority: Priority
    var position: CGPoint = .zero       // Calculated by layout engine

    init(from todo: Todo) {
        self.id = todo.id
        self.title = todo.title
        self.isCompleted = todo.isCompleted
        self.priority = todo.priority
    }
}

// MARK: - Goal Section with Tag
struct GoalSectionWithTag: Identifiable {
    let id = UUID()
    let title: String       // Clean title without #tag
    let tag: String         // Extracted tag
    var items: [String]     // Sub-bullets from the goal section (mutable for building)
}
