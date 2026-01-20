import SwiftUI

// MARK: - Organic Branch Shape
/// An organic curved branch line like in classic mind maps
struct OrganicBranch: Shape {
    let start: CGPoint
    let end: CGPoint
    let isRightSide: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Calculate control points for organic S-curve
        let dx = end.x - start.x
        let dy = end.y - start.y

        // Control points create a smooth horizontal-to-vertical curve
        let control1 = CGPoint(
            x: start.x + dx * 0.6,
            y: start.y + dy * 0.1
        )
        let control2 = CGPoint(
            x: start.x + dx * 0.9,
            y: end.y
        )

        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)

        return path
    }
}

// MARK: - Branch Line View
/// Renders an organic curved branch with color
struct BranchLineView: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    var lineWidth: CGFloat = 3
    var isRightSide: Bool = true

    var body: some View {
        OrganicBranch(start: from, end: to, isRightSide: isRightSide)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
    }
}

// MARK: - Center to Branch Connection
/// Connection from center node to a main branch
struct CenterBranchLine: Shape {
    let centerPoint: CGPoint
    let branchPoint: CGPoint
    let isRightSide: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let dx = branchPoint.x - centerPoint.x
        let dy = branchPoint.y - centerPoint.y

        // Smooth curve from center outward
        let control1 = CGPoint(
            x: centerPoint.x + dx * 0.4,
            y: centerPoint.y
        )
        let control2 = CGPoint(
            x: centerPoint.x + dx * 0.7,
            y: branchPoint.y
        )

        path.move(to: centerPoint)
        path.addCurve(to: branchPoint, control1: control1, control2: control2)

        return path
    }
}

// MARK: - Center Branch View
struct CenterBranchView: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    var lineWidth: CGFloat = 4

    var isRightSide: Bool {
        to.x > from.x
    }

    var body: some View {
        CenterBranchLine(centerPoint: from, branchPoint: to, isRightSide: isRightSide)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
    }
}

// MARK: - Child Branch Line
/// Thinner branch from parent to child
struct ChildBranchView: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color

    var isRightSide: Bool {
        to.x > from.x
    }

    var body: some View {
        OrganicBranch(start: from, end: to, isRightSide: isRightSide)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
    }
}

// MARK: - Legacy Support (keep for compatibility)
struct ConnectionLine: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let dx = end.x - start.x
        let dy = end.y - start.y

        let control1 = CGPoint(
            x: start.x + dx * 0.5,
            y: start.y
        )
        let control2 = CGPoint(
            x: end.x - dx * 0.2,
            y: end.y
        )

        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)

        return path
    }
}

struct ConnectionLineView: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    var isHighlighted: Bool = false
    var lineWidth: CGFloat = 2

    var body: some View {
        ConnectionLine(start: from, end: to)
            .stroke(
                color.opacity(isHighlighted ? 0.9 : 0.7),
                style: StrokeStyle(
                    lineWidth: isHighlighted ? lineWidth + 1 : lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .animation(Theme.Animation.quickFade, value: isHighlighted)
    }
}
