import SwiftUI

// MARK: - Mind Map Layout Engine
/// Calculates positions for mind map nodes using a horizontal tree layout
/// Nodes spread left and right from a central point, like a classic mind map
struct MindMapLayout {

    // MARK: - Configuration

    /// Horizontal spacing from center to main branches
    static let centerToMainBranch: CGFloat = 200

    /// Horizontal spacing from main branch to children
    static let branchToChildSpacing: CGFloat = 200

    /// Vertical spacing between sibling main branches (when collapsed)
    static let mainBranchSpacing: CGFloat = 20

    /// Vertical spacing between child nodes
    static let childSpacing: CGFloat = 44

    /// Node dimensions
    static let rootNodeWidth: CGFloat = 160
    static let rootNodeHeight: CGFloat = 50
    static let childNodeWidth: CGFloat = 200
    static let childNodeHeight: CGFloat = 26

    // MARK: - Layout Calculation

    /// Height per goal item in the goal box
    static let goalItemHeight: CGFloat = 20

    /// Calculates positions for all nodes in a horizontal tree layout
    /// Pass expandedNodeIds and expandedGoalIds to dynamically adjust spacing
    static func calculateLayout(nodes: [MindMapNode], center: CGPoint, expandedNodeIds: Set<UUID> = [], expandedGoalIds: Set<UUID> = []) -> [MindMapNode] {
        guard !nodes.isEmpty else { return [] }

        var positionedNodes = nodes

        // Split nodes into left and right sides for balance
        let halfCount = (nodes.count + 1) / 2
        let rightIndices = Array(0..<halfCount)
        let leftIndices = Array(halfCount..<nodes.count)

        // Position right side nodes
        positionSide(
            indices: rightIndices,
            nodes: &positionedNodes,
            center: center,
            isRightSide: true,
            expandedNodeIds: expandedNodeIds,
            expandedGoalIds: expandedGoalIds
        )

        // Position left side nodes
        positionSide(
            indices: leftIndices,
            nodes: &positionedNodes,
            center: center,
            isRightSide: false,
            expandedNodeIds: expandedNodeIds,
            expandedGoalIds: expandedGoalIds
        )

        return positionedNodes
    }

    /// Position nodes on one side (left or right)
    private static func positionSide(
        indices: [Int],
        nodes: inout [MindMapNode],
        center: CGPoint,
        isRightSide: Bool,
        expandedNodeIds: Set<UUID>,
        expandedGoalIds: Set<UUID>
    ) {
        guard !indices.isEmpty else { return }

        // Calculate total height needed for this side
        var totalHeight: CGFloat = 0
        for index in indices {
            let isExpanded = expandedNodeIds.contains(nodes[index].id)
            let isGoalExpanded = expandedGoalIds.contains(nodes[index].id)
            totalHeight += calculateBranchHeight(node: nodes[index], isExpanded: isExpanded, isGoalExpanded: isGoalExpanded)
        }
        totalHeight += CGFloat(indices.count - 1) * mainBranchSpacing

        // Start positioning from top
        var currentY = center.y - totalHeight / 2
        let direction: CGFloat = isRightSide ? 1 : -1

        for index in indices {
            let isExpanded = expandedNodeIds.contains(nodes[index].id)
            let isGoalExpanded = expandedGoalIds.contains(nodes[index].id)
            let branchHeight = calculateBranchHeight(node: nodes[index], isExpanded: isExpanded, isGoalExpanded: isGoalExpanded)

            // Main branch position
            let branchX = center.x + (centerToMainBranch * direction)
            let branchY = currentY + branchHeight / 2

            nodes[index].position = CGPoint(x: branchX, y: branchY)

            // Position todo children - further out and spread vertically
            // (Goal items are shown in the branch node itself, not as separate nodes)
            let childCount = nodes[index].children.count

            if childCount > 0 {
                let childX = branchX + (branchToChildSpacing * direction)
                let childrenHeight = CGFloat(childCount - 1) * childSpacing
                var itemY = branchY - childrenHeight / 2

                for i in 0..<childCount {
                    nodes[index].children[i].position = CGPoint(x: childX, y: itemY)
                    itemY += childSpacing
                }
            }

            currentY += branchHeight + mainBranchSpacing
        }
    }

    /// Calculate the height needed for a branch
    /// Accounts for: base height, expanded children, and expanded goal box
    private static func calculateBranchHeight(node: MindMapNode, isExpanded: Bool, isGoalExpanded: Bool) -> CGFloat {
        var height = rootNodeHeight

        // Add height for expanded children
        if isExpanded {
            let childCount = node.children.count
            if childCount > 1 {
                height = max(height, CGFloat(childCount) * childSpacing)
            }
        }

        // Add height for expanded goal box
        if isGoalExpanded && !node.goalItems.isEmpty {
            let goalBoxHeight = CGFloat(node.goalItems.count) * goalItemHeight + 30 // padding
            height += goalBoxHeight
        }

        return height
    }

    // MARK: - Canvas Size Calculation

    /// Calculates the minimum canvas size needed to display all nodes
    static func calculateCanvasSize(nodes: [MindMapNode], padding: CGFloat = 200) -> CGSize {
        guard !nodes.isEmpty else {
            return CGSize(width: 1400, height: 900)
        }

        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        for node in nodes {
            // Check root node position
            minX = min(minX, node.position.x - rootNodeWidth)
            maxX = max(maxX, node.position.x + rootNodeWidth)
            minY = min(minY, node.position.y - rootNodeHeight)
            maxY = max(maxY, node.position.y + rootNodeHeight)

            // Check child positions
            for child in node.children {
                minX = min(minX, child.position.x - childNodeWidth)
                maxX = max(maxX, child.position.x + childNodeWidth)
                minY = min(minY, child.position.y - childNodeHeight)
                maxY = max(maxY, child.position.y + childNodeHeight)
            }
        }

        let width = maxX - minX + padding * 2
        let height = maxY - minY + padding * 2

        return CGSize(width: max(width, 1400), height: max(height, 900))
    }
}
