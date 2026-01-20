import SwiftUI

// MARK: - Mind Map View
/// Main container for the mind map visualization with pan/zoom support
struct MindMapView: View {
    @ObservedObject var todoList: TodoList

    // View state
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var selectedNodeId: UUID? = nil
    @State private var expandedNodeIds: Set<UUID> = []
    @State private var expandedGoalIds: Set<UUID> = []  // Track which goal boxes are open

    // Calculated layout
    @State private var positionedNodes: [MindMapNode] = []
    @State private var canvasSize: CGSize = CGSize(width: 1400, height: 900)
    @State private var centerPoint: CGPoint = CGPoint(x: 700, y: 450)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Theme.mainBackgroundGradient
                    .ignoresSafeArea()

                if positionedNodes.isEmpty {
                    MindMapEmptyState()
                } else {
                    // Mind map canvas - centered in scroll view
                    ScrollViewReader { scrollProxy in
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            ZStack {
                                // Invisible anchor at center for scrolling
                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .id("center")
                                    .position(centerPoint)

                                MindMapCanvas(
                                    nodes: positionedNodes,
                                    canvasSize: canvasSize,
                                    centerPoint: centerPoint,
                                    selectedNodeId: $selectedNodeId,
                                    expandedNodeIds: $expandedNodeIds,
                                    expandedGoalIds: $expandedGoalIds,
                                    onToggleTodo: toggleTodo
                                )
                            }
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .scaleEffect(scale)
                        }
                        .onAppear {
                            // Scroll to center on appear
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    scrollProxy.scrollTo("center", anchor: .center)
                                }
                            }
                        }
                    }
                    .background(GridPattern().opacity(0.2))
                }

                // Controls overlay
                VStack {
                    HStack {
                        Spacer()
                        if !positionedNodes.isEmpty {
                            MindMapStatsView(nodes: positionedNodes)
                                .padding(.top, 12)
                                .padding(.trailing, 12)
                        }
                    }

                    Spacer()

                    HStack {
                        Spacer()
                        MindMapControls(
                            scale: $scale,
                            offset: $offset,
                            onResetView: resetView
                        )
                        .padding(.bottom, 12)
                        .padding(.trailing, 12)
                    }
                }
            }
            .onAppear {
                updateLayout(viewSize: geometry.size)
            }
            .onChange(of: todoList.goals) { _ in
                updateLayout(viewSize: geometry.size)
            }
            .onChange(of: todoList.todos) { _ in
                updateLayout(viewSize: geometry.size)
            }
            .onChange(of: todoList.top5Todos) { _ in
                updateLayout(viewSize: geometry.size)
            }
            .onChange(of: expandedNodeIds) { _ in
                updateLayout(viewSize: geometry.size)
            }
            .onChange(of: expandedGoalIds) { _ in
                updateLayout(viewSize: geometry.size)
            }
        }
    }

    // MARK: - Layout

    private func updateLayout(viewSize: CGSize) {
        let nodes = todoList.mindMapNodes

        // Canvas should be large enough to fit content with room to scroll
        let canvasWidth = max(viewSize.width * 2, 1400)
        let canvasHeight = max(viewSize.height * 2, 900)
        let center = CGPoint(x: canvasWidth / 2, y: canvasHeight / 2)

        let newPositionedNodes = MindMapLayout.calculateLayout(
            nodes: nodes,
            center: center,
            expandedNodeIds: expandedNodeIds,
            expandedGoalIds: expandedGoalIds
        )
        let newCanvasSize = CGSize(width: canvasWidth, height: canvasHeight)

        // Defer state updates to avoid modifying state during view update
        DispatchQueue.main.async {
            positionedNodes = newPositionedNodes
            canvasSize = newCanvasSize
            centerPoint = center
        }
    }

    private func resetView() {
        withAnimation(Theme.Animation.spring) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    private func toggleTodo(_ todoId: UUID) {
        if let todo = todoList.todos.first(where: { $0.id == todoId }) {
            todoList.toggleTodo(todo)
        } else if let todo = todoList.top5Todos.first(where: { $0.id == todoId }) {
            todoList.toggleTop5Todo(todo)
        }
    }
}

// MARK: - Grid Pattern
struct GridPattern: View {
    let spacing: CGFloat = 40
    let lineWidth: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                var x: CGFloat = 0
                while x < geometry.size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    x += spacing
                }

                var y: CGFloat = 0
                while y < geometry.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(Theme.divider.opacity(0.2), lineWidth: lineWidth)
        }
    }
}
