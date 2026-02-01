import SwiftUI

enum Theme {
    // Colors
    static let background = Color(.windowBackgroundColor)
    static let secondaryBackground = Color(NSColor.controlAccentColor.withAlphaComponent(0.1))
    static let accent = Color(NSColor.controlAccentColor)
    static let text = Color.primary
    static let secondaryText = Color(NSColor.secondaryLabelColor)
    static let divider = Color(NSColor.separatorColor)
    
    // Selection colors
    static let selectionBackground = Color(NSColor.selectedContentBackgroundColor)
    static let selectionInactiveBackground = Color(NSColor.unemphasizedSelectedContentBackgroundColor)
    static let selectionText = Color(NSColor.selectedContentBackgroundColor)
    
    // Font sizes
    static let titleFont: Font = .title2.bold()
    static let headlineFont: Font = .headline
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let smallFont = Font.system(size: 11, weight: .regular)
    
    // Spacing
    static let itemSpacing: CGFloat = 4
    static let sectionSpacing: CGFloat = 24
    static let contentPadding: CGFloat = 16
    
    // Corners
    static let cornerRadius: CGFloat = 6
    static let cornerRadiusMd: CGFloat = 8
    static let cornerRadiusLg: CGFloat = 12

    // MARK: - Animations
    enum Animation {
        /// Primary spring animation for most interactions
        static let spring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        /// Faster spring for micro-interactions (hover, press)
        static let microSpring = SwiftUI.Animation.spring(response: 0.2, dampingFraction: 0.8)
        /// Smooth easing for panel slides
        static let panelSlide = SwiftUI.Animation.easeInOut(duration: 0.25)
        /// Quick fade for opacity changes
        static let quickFade = SwiftUI.Animation.easeOut(duration: 0.15)
    }

    // MARK: - Shadows
    enum Shadow {
        /// Subtle card shadow for depth
        static let cardColor = Color.black.opacity(0.04)
        static let cardRadius: CGFloat = 8
        static let cardY: CGFloat = 2
        /// Hover state shadow
        static let hoverColor = Color.black.opacity(0.06)
        static let hoverRadius: CGFloat = 12
        static let hoverY: CGFloat = 3
    }
    
    // Updated Tag Colors - More like Things3
    private static let tagColors: [Color] = [
        Color(NSColor(red: 0.40, green: 0.65, blue: 0.95, alpha: 1.0)),  // Blue
        Color(NSColor(red: 0.45, green: 0.75, blue: 0.45, alpha: 1.0)),  // Green
        Color(NSColor(red: 0.75, green: 0.55, blue: 0.95, alpha: 1.0)),  // Purple
        Color(NSColor(red: 0.55, green: 0.75, blue: 0.85, alpha: 1.0)),  // Light Blue

        Color(NSColor(red: 0.95, green: 0.78, blue: 0.45, alpha: 1.0)),  // Golden Yellow
        Color(NSColor(red: 0.65, green: 0.45, blue: 0.85, alpha: 1.0)),  // Violet
        Color(NSColor(red: 0.85, green: 0.85, blue: 0.35, alpha: 1.0)),  // Yellow
        Color(NSColor(red: 0.85, green: 0.65, blue: 0.85, alpha: 1.0)),  // Light Purple
        Color(NSColor(red: 0.50, green: 0.85, blue: 0.75, alpha: 1.0)),  // Teal
        Color(NSColor(red: 0.45, green: 0.85, blue: 0.65, alpha: 1.0)),  // Mint
        Color(NSColor(red: 0.70, green: 0.60, blue: 0.45, alpha: 1.0)),  // Brown
        Color(NSColor(red: 0.45, green: 0.60, blue: 0.70, alpha: 1.0)),  // Steel Blue
        Color(NSColor(red: 0.60, green: 0.75, blue: 0.45, alpha: 1.0)),  // Olive Green
        Color(NSColor(red: 0.45, green: 0.75, blue: 0.85, alpha: 1.0)),  // Sky Blue
        Color(NSColor(red: 0.65, green: 0.45, blue: 0.65, alpha: 1.0)),  // Plum
        Color(NSColor(red: 0.55, green: 0.65, blue: 0.45, alpha: 1.0)),  // Sage
        Color(NSColor(red: 0.75, green: 0.65, blue: 0.85, alpha: 1.0)),  // Lavender
        Color(NSColor(red: 0.45, green: 0.85, blue: 0.85, alpha: 1.0)),  // Cyan
        Color(NSColor(red: 0.75, green: 0.75, blue: 0.55, alpha: 1.0)),  // Khaki
        Color(NSColor(red: 0.55, green: 0.45, blue: 0.75, alpha: 1.0))   // Indigo
    ]

    // Urgency tag colors
    static let todayTagColor = Color(red: 0.95, green: 0.2, blue: 0.2)      // Bright red for #today
    static let urgentTagColor = Color(red: 1.0, green: 0.5, blue: 0.0)      // Orange for #urgent

    // Context tag colors (pre-assigned for consistency)
    static let contextTagColors: [String: Color] = [
        "prep": Color(red: 0.4, green: 0.6, blue: 0.9),      // Blue - meeting prep
        "reply": Color(red: 0.5, green: 0.8, blue: 0.5),     // Green
        "deep": Color(red: 0.7, green: 0.5, blue: 0.9),      // Purple
        "waiting": Color(red: 0.6, green: 0.6, blue: 0.6)    // Gray
    ]
    
    // Track used colors and tag assignments
    private static var usedColors: Set<Int> = []
    private static var tagColorMap: [String: Color] = [:]
    
    // Function to get consistent color for a tag
    static func colorForTag(_ tag: String) -> Color {
        let tagKey = tag.lowercased()

        // 1. Check urgency tags first (highest priority)
        if tagKey == "today" {
            return todayTagColor
        }
        if tagKey == "urgent" {
            return urgentTagColor
        }

        // 2. Check context tags (pre-assigned colors)
        if let contextColor = contextTagColors[tagKey] {
            return contextColor
        }

        // 3. Return cached color if already assigned
        if let existingColor = tagColorMap[tagKey] {
            return existingColor
        }

        // If all colors are used, reset the pool
        if usedColors.count >= tagColors.count {
            usedColors.removeAll()
        }

        // Generate hash for initial index
        var hash: UInt64 = 5381
        for char in tag.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(char.value)
        }
        hash = (hash &* 31337) ^ (hash >> 16)

        // Find first available color starting from the hashed index
        var index = Int(hash % UInt64(tagColors.count))
        while usedColors.contains(index) {
            index = (index + 1) % tagColors.count
        }

        // Mark color as used and cache the assignment
        usedColors.insert(index)
        let color = tagColors[index]
        tagColorMap[tagKey] = color

        return color
    }
    
    // Reset color assignments (can be called when needed)
    static func resetTagColors() {
        usedColors.removeAll()
        tagColorMap.removeAll()
    }
    
    // Dynamic background gradient based on selected theme
    static var mainBackgroundGradient: some View {
        ThemeManager.shared.currentGradient
    }
}

// MARK: - Theme Presets
enum GradientTheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case aurora = "Aurora"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case forest = "Forest"
    case lavender = "Lavender"
    case midnight = "Midnight"
    case coral = "Coral"
    case mint = "Mint"

    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .classic:
            return [
                Color(NSColor.windowBackgroundColor),
                Color(NSColor.windowBackgroundColor)
            ]
        case .aurora:
            return [
                Color(red: 0.1, green: 0.2, blue: 0.4),
                Color(red: 0.2, green: 0.3, blue: 0.5),
                Color(red: 0.3, green: 0.2, blue: 0.5),
                Color(red: 0.2, green: 0.4, blue: 0.4)
            ]
        case .sunset:
            return [
                Color(red: 0.95, green: 0.4, blue: 0.3),
                Color(red: 0.9, green: 0.5, blue: 0.4),
                Color(red: 0.85, green: 0.45, blue: 0.5),
                Color(red: 0.4, green: 0.3, blue: 0.5)
            ]
        case .ocean:
            return [
                Color(red: 0.1, green: 0.3, blue: 0.5),
                Color(red: 0.15, green: 0.4, blue: 0.55),
                Color(red: 0.2, green: 0.5, blue: 0.6),
                Color(red: 0.1, green: 0.35, blue: 0.45)
            ]
        case .forest:
            return [
                Color(red: 0.15, green: 0.3, blue: 0.2),
                Color(red: 0.2, green: 0.35, blue: 0.25),
                Color(red: 0.25, green: 0.4, blue: 0.3),
                Color(red: 0.15, green: 0.25, blue: 0.2)
            ]
        case .lavender:
            return [
                Color(red: 0.4, green: 0.35, blue: 0.55),
                Color(red: 0.5, green: 0.4, blue: 0.6),
                Color(red: 0.45, green: 0.35, blue: 0.5),
                Color(red: 0.35, green: 0.3, blue: 0.45)
            ]
        case .midnight:
            return [
                Color(red: 0.08, green: 0.1, blue: 0.2),
                Color(red: 0.12, green: 0.15, blue: 0.28),
                Color(red: 0.1, green: 0.12, blue: 0.22),
                Color(red: 0.06, green: 0.08, blue: 0.16)
            ]
        case .coral:
            return [
                Color(red: 0.9, green: 0.5, blue: 0.45),
                Color(red: 0.85, green: 0.55, blue: 0.5),
                Color(red: 0.8, green: 0.45, blue: 0.45),
                Color(red: 0.6, green: 0.35, blue: 0.4)
            ]
        case .mint:
            return [
                Color(red: 0.3, green: 0.55, blue: 0.5),
                Color(red: 0.35, green: 0.6, blue: 0.55),
                Color(red: 0.4, green: 0.65, blue: 0.6),
                Color(red: 0.25, green: 0.5, blue: 0.45)
            ]
        }
    }

    var previewGradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var isLight: Bool {
        switch self {
        case .classic: return true
        case .aurora, .sunset, .ocean, .forest, .lavender, .midnight, .coral, .mint: return false
        }
    }
}

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var selectedTheme: GradientTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "selectedTheme")
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = GradientTheme(rawValue: saved) {
            self.selectedTheme = theme
        } else {
            self.selectedTheme = .classic
        }
    }

    var currentGradient: some View {
        ZStack {
            if selectedTheme == .classic {
                Color(NSColor.windowBackgroundColor)
            } else {
                MeshGradientView(colors: selectedTheme.colors)
            }
        }
    }

    var textColor: Color {
        selectedTheme.isLight ? Color.primary : Color.white
    }

    var secondaryTextColor: Color {
        selectedTheme.isLight ? Color(NSColor.secondaryLabelColor) : Color.white.opacity(0.7)
    }
}

// MARK: - Mesh Gradient View (Modern multi-color gradient)
struct MeshGradientView: View {
    let colors: [Color]
    @State private var animate = false

    var body: some View {
        ZStack {
            // Base layer
            LinearGradient(
                colors: colors,
                startPoint: animate ? .topLeading : .topTrailing,
                endPoint: animate ? .bottomTrailing : .bottomLeading
            )

            // Overlay blobs for depth
            GeometryReader { geo in
                Circle()
                    .fill(colors.first?.opacity(0.4) ?? Color.clear)
                    .blur(radius: 80)
                    .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.8)
                    .offset(
                        x: animate ? geo.size.width * 0.1 : geo.size.width * -0.2,
                        y: animate ? geo.size.height * -0.1 : geo.size.height * 0.1
                    )

                Circle()
                    .fill(colors.last?.opacity(0.3) ?? Color.clear)
                    .blur(radius: 100)
                    .frame(width: geo.size.width * 0.7, height: geo.size.width * 0.7)
                    .offset(
                        x: animate ? geo.size.width * 0.3 : geo.size.width * 0.5,
                        y: animate ? geo.size.height * 0.5 : geo.size.height * 0.3
                    )

                if colors.count > 2 {
                    Circle()
                        .fill(colors[1].opacity(0.25))
                        .blur(radius: 60)
                        .frame(width: geo.size.width * 0.5, height: geo.size.width * 0.5)
                        .offset(
                            x: animate ? geo.size.width * 0.6 : geo.size.width * 0.4,
                            y: animate ? geo.size.height * 0.2 : geo.size.height * 0.4
                        )
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
} 