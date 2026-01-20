import SwiftUI

// MARK: - Mind Map Canvas
/// Renders the mind map with a central node and branches spreading left/right
struct MindMapCanvas: View {
    let nodes: [MindMapNode]
    let canvasSize: CGSize
    let centerPoint: CGPoint
    @Binding var selectedNodeId: UUID?
    @Binding var expandedNodeIds: Set<UUID>
    @Binding var expandedGoalIds: Set<UUID>
    var onToggleTodo: ((UUID) -> Void)?

    // Child node width for calculating connection endpoints
    private let childNodeWidth: CGFloat = 220

    var body: some View {
        ZStack {
            // Layer 1: Branch connections from center to main nodes
            ForEach(nodes) { node in
                CenterBranchView(
                    from: centerPoint,
                    to: node.position,
                    color: node.color,
                    lineWidth: 4
                )
            }

            // Layer 2: Child branch connections (only for expanded nodes)
            ForEach(nodes) { node in
                if expandedNodeIds.contains(node.id) {
                    // Todo child connections
                    ForEach(node.children) { child in
                        let childEdgeX = child.position.x
                        let childEndpoint = CGPoint(x: childEdgeX, y: child.position.y)

                        ChildBranchView(
                            from: node.position,
                            to: childEndpoint,
                            color: node.color
                        )
                        .transition(.opacity)
                    }
                }
            }

            // Layer 3: Child nodes (only for expanded nodes)
            ForEach(nodes) { node in
                if expandedNodeIds.contains(node.id) {
                    let isRightSide = node.position.x > centerPoint.x

                    // Todo children only (goal items shown in branch node)
                    ForEach(node.children) { child in
                        LeafNodeView(
                            child: child,
                            color: node.color,
                            isRightSide: isRightSide,
                            onToggleComplete: {
                                onToggleTodo?(child.id)
                            }
                        )
                        .position(
                            x: isRightSide
                                ? child.position.x + childNodeWidth / 2
                                : child.position.x - childNodeWidth / 2,
                            y: child.position.y
                        )
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
            }

            // Layer 4: Main branch nodes
            ForEach(nodes) { node in
                let isRightSide = node.position.x > centerPoint.x
                BranchNodeView(
                    node: node,
                    isExpanded: expandedNodeIds.contains(node.id),
                    isGoalExpanded: expandedGoalIds.contains(node.id),
                    isRightSide: isRightSide,
                    onToggleExpand: {
                        withAnimation(Theme.Animation.spring) {
                            if expandedNodeIds.contains(node.id) {
                                expandedNodeIds.remove(node.id)
                            } else {
                                expandedNodeIds.insert(node.id)
                            }
                        }
                    },
                    onToggleGoalExpand: {
                        withAnimation(Theme.Animation.spring) {
                            if expandedGoalIds.contains(node.id) {
                                expandedGoalIds.remove(node.id)
                            } else {
                                expandedGoalIds.insert(node.id)
                            }
                        }
                    }
                )
                .position(node.position)
            }

            // Layer 5: Central node (on top)
            CentralNodeView(title: "Mind Map")
                .position(centerPoint)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}

// MARK: - Connections For Node (Legacy support)
struct ConnectionsForNode: View {
    let node: MindMapNode

    var body: some View {
        ForEach(node.children) { child in
            ChildBranchView(
                from: node.position,
                to: child.position,
                color: node.color
            )
        }
    }
}

// MARK: - Empty State View
struct MindMapEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundColor(Theme.secondaryText.opacity(0.5))

            Text("No Mind Map Data")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.text)

            Text("Add hashtags to your goals to see them here.\nExample: **People Management** #people")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mind Map Statistics View
struct MindMapStatsView: View {
    let nodes: [MindMapNode]

    private var stats: (totalNodes: Int, totalTodos: Int, goalSectionCount: Int, orphanTagCount: Int) {
        MindMapDataBuilder.getStatistics(for: nodes)
    }

    var body: some View {
        HStack(spacing: 16) {
            StatItem(label: "Categories", value: "\(stats.totalNodes)", icon: "point.3.connected.trianglepath.dotted")
            StatItem(label: "Todos", value: "\(stats.totalTodos)", icon: "checklist")
            StatItem(label: "From Goals", value: "\(stats.goalSectionCount)", icon: "target")
            if stats.orphanTagCount > 0 {
                StatItem(label: "Orphan Tags", value: "\(stats.orphanTagCount)", icon: "tag")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.95))
                .shadow(color: Theme.Shadow.cardColor, radius: Theme.Shadow.cardRadius, y: Theme.Shadow.cardY)
        )
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)

                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(Theme.secondaryText)
            }
        }
    }
}
