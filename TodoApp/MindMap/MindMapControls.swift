import SwiftUI

// MARK: - Mind Map Controls
/// Floating controls for zoom, pan, and reset functionality
struct MindMapControls: View {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    var onResetView: () -> Void

    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 2.0
    private let scaleStep: CGFloat = 0.2

    var body: some View {
        VStack(spacing: 8) {
            // Zoom In
            ControlButton(icon: "plus.magnifyingglass", action: zoomIn)
                .help("Zoom In")

            // Zoom percentage indicator
            Text("\(Int(scale * 100))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 36)

            // Zoom Out
            ControlButton(icon: "minus.magnifyingglass", action: zoomOut)
                .help("Zoom Out")

            Divider()
                .frame(width: 24)
                .padding(.vertical, 4)

            // Reset View
            ControlButton(icon: "arrow.counterclockwise", action: onResetView)
                .help("Reset View")

            // Fit to Screen
            ControlButton(icon: "arrow.up.left.and.arrow.down.right", action: fitToScreen)
                .help("Fit to Screen")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.95))
                .shadow(color: Theme.Shadow.cardColor, radius: Theme.Shadow.cardRadius, y: Theme.Shadow.cardY)
        )
    }

    private func zoomIn() {
        withAnimation(Theme.Animation.microSpring) {
            scale = min(maxScale, scale + scaleStep)
        }
    }

    private func zoomOut() {
        withAnimation(Theme.Animation.microSpring) {
            scale = max(minScale, scale - scaleStep)
        }
    }

    private func fitToScreen() {
        withAnimation(Theme.Animation.spring) {
            scale = 1.0
            offset = .zero
        }
    }
}

// MARK: - Control Button
struct ControlButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isHovered ? Theme.accent : Theme.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(isHovered ? Theme.accent.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(Theme.Animation.quickFade, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - View Mode Toggle
/// Toggle button to switch between list and mind map views
struct ViewModeToggle: View {
    @Binding var isInMindMapMode: Bool

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            withAnimation(Theme.Animation.panelSlide) {
                isInMindMapMode.toggle()
            }
        }) {
            Image(systemName: isInMindMapMode ? "list.bullet" : "circle.grid.cross")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isInMindMapMode ? Theme.accent : Theme.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(isInMindMapMode ? Theme.accent.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(isInMindMapMode ? "Switch to List View" : "Switch to Mind Map View")
        .animation(Theme.Animation.quickFade, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Quick Actions Bar
/// Floating bar with quick actions for the mind map
struct QuickActionsBar: View {
    @Binding var selectedNodeId: UUID?
    var onCollapseAll: () -> Void
    var onExpandAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if selectedNodeId != nil {
                Button(action: {
                    withAnimation(Theme.Animation.microSpring) {
                        selectedNodeId = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Deselect")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Theme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Theme.secondaryBackground)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
