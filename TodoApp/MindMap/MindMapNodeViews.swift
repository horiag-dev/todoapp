import SwiftUI

// MARK: - Central Node View
/// The main central node of the mind map - simple circle with icon
struct CentralNodeView: View {
    let title: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(NSColor.textBackgroundColor))
                .frame(width: 56, height: 56)
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)

            Circle()
                .stroke(Theme.accent.opacity(0.4), lineWidth: 2)
                .frame(width: 56, height: 56)

            Image(systemName: "checklist")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Theme.accent)
        }
    }
}

// MARK: - Branch Node View (Main branches from center)
/// A main branch node - text with expand button, shows goal items in a box underneath
struct BranchNodeView: View {
    let node: MindMapNode
    var isExpanded: Bool = false
    var isGoalExpanded: Bool = false
    var isRightSide: Bool = true
    var onToggleExpand: (() -> Void)? = nil
    var onToggleGoalExpand: (() -> Void)? = nil

    @State private var isHovered = false

    // Fixed width for the branch node component
    private let branchWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: isRightSide ? .leading : .trailing, spacing: 6) {
            // Main branch row
            branchHeader

            // Goal items box (shown when toggled)
            if isGoalExpanded && !node.goalItems.isEmpty {
                goalItemsBox
                    .frame(width: branchWidth)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(Theme.Animation.quickFade, value: isHovered)
        .animation(Theme.Animation.spring, value: isGoalExpanded)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var branchHeader: some View {
        HStack(spacing: 8) {
            // Left side: expand button on left
            if !isRightSide {
                expandButton
            }

            // Branch title - flexible width
            Text(node.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: isRightSide ? .leading : .trailing)

            // Goal items toggle (if any)
            if !node.goalItems.isEmpty {
                goalItemsToggle
            }

            // Right side: expand button on right
            if isRightSide {
                expandButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: branchWidth)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(node.color.opacity(0.5), lineWidth: 2)
        )
        .shadow(color: node.color.opacity(0.15), radius: 4, y: 2)
    }

    private var todoCount: Int {
        node.children.count
    }

    @ViewBuilder
    private var expandButton: some View {
        if todoCount > 0 {
            Button(action: {
                withAnimation(Theme.Animation.spring) {
                    onToggleExpand?()
                }
            }) {
                HStack(spacing: 4) {
                    Text("\(todoCount)")
                        .font(.system(size: 12, weight: .bold))

                    Image(systemName: isExpanded ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isRightSide ? 0 : 180))
                }
                .foregroundColor(isExpanded ? .white : node.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isExpanded ? node.color : node.color.opacity(0.2))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isHovered ? 1.1 : 1.0)
        }
    }

    private var goalItemsToggle: some View {
        Button(action: {
            onToggleGoalExpand?()
        }) {
            Image(systemName: "target")
                .font(.system(size: 12))
                .foregroundColor(isGoalExpanded ? .white : node.color.opacity(0.7))
                .padding(6)
                .background(
                    Circle()
                        .fill(isGoalExpanded ? node.color.opacity(0.8) : node.color.opacity(0.15))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var goalItemsBox: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(node.goalItems) { item in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(node.color)
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)

                    Text(item.title)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.textBackgroundColor))
                RoundedRectangle(cornerRadius: 8)
                    .fill(node.color.opacity(0.08))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(node.color.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Leaf Node View (Child nodes - todos)
/// A child/leaf node showing a todo - simple text style
struct LeafNodeView: View {
    let child: MindMapChildNode
    let color: Color
    var isRightSide: Bool = true
    var onToggleComplete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // For LEFT side: priority flag, text, checkbox (reading right to left toward connection)
            // For RIGHT side: checkbox, text, priority flag (reading left to right from connection)

            if isRightSide {
                // Right side: checkbox first (near connection point)
                checkboxButton
                todoText
                priorityFlag
            } else {
                // Left side: priority flag, text, checkbox (checkbox near connection point)
                priorityFlag
                todoText
                checkboxButton
            }
        }
        .frame(width: 220, alignment: isRightSide ? .leading : .trailing)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(isHovered ? 0.4 : 0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
        .opacity(child.isCompleted ? 0.6 : 1.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(Theme.Animation.quickFade, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(action: {
                onToggleComplete?()
            }) {
                Label(
                    child.isCompleted ? "Mark as Incomplete" : "Mark as Complete",
                    systemImage: child.isCompleted ? "circle" : "checkmark.circle"
                )
            }
        }
    }

    private var checkboxButton: some View {
        Button(action: {
            onToggleComplete?()
        }) {
            Image(systemName: child.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundColor(child.isCompleted ? .green : color.opacity(0.5))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var todoText: some View {
        Text(child.title)
            .font(.system(size: 12))
            .foregroundColor(child.isCompleted ? Theme.secondaryText : Theme.text)
            .strikethrough(child.isCompleted)
            .lineLimit(2)  // Allow up to 2 lines for longer todos
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: isRightSide ? .leading : .trailing)
    }

    @ViewBuilder
    private var priorityFlag: some View {
        if child.priority == .thisWeek {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 9))
                .foregroundColor(child.priority.color)
        } else if child.priority == .urgent {
            Image(systemName: "flag.fill")
                .font(.system(size: 9))
                .foregroundColor(child.priority.color)
        }
    }
}

// MARK: - Goal Item View (from goal section bullets)
/// A goal item - simple text without checkbox
struct GoalItemView: View {
    let item: MindMapGoalItem
    let color: Color
    var isRightSide: Bool = true

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if isRightSide {
                // Right side: icon first (near connection point)
                goalIcon
                goalText
            } else {
                // Left side: text, then icon (icon near connection point)
                goalText
                goalIcon
            }
        }
        .frame(width: 220, alignment: isRightSide ? .leading : .trailing)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(isHovered ? 0.4 : 0.25), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(Theme.Animation.quickFade, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var goalIcon: some View {
        Image(systemName: "target")
            .font(.system(size: 11))
            .foregroundColor(color.opacity(0.7))
    }

    private var goalText: some View {
        Text(item.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.text.opacity(0.85))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: isRightSide ? .leading : .trailing)
    }
}

// MARK: - Legacy compatibility wrappers
struct RootNodeView: View {
    let node: MindMapNode
    var isSelected: Bool = false
    var isExpanded: Bool = false
    var onTap: (() -> Void)? = nil
    var onToggleExpand: (() -> Void)? = nil

    var body: some View {
        BranchNodeView(
            node: node,
            isExpanded: isExpanded,
            isRightSide: true,
            onToggleExpand: onToggleExpand
        )
    }
}

struct ChildNodeView: View {
    let child: MindMapChildNode
    let color: Color
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil
    var onToggleComplete: (() -> Void)? = nil

    var body: some View {
        LeafNodeView(
            child: child,
            color: color,
            isRightSide: true,
            onToggleComplete: onToggleComplete
        )
    }
}

