import SwiftUI

enum Theme {
    // Colors
    static let background = Color(.windowBackgroundColor)
    static let secondaryBackground = Color(NSColor.controlAccentColor.withAlphaComponent(0.1))
    static let accent = Color(NSColor.controlAccentColor)
    static let text = Color.primary
    static let secondaryText = Color(NSColor.secondaryLabelColor)
    static let divider = Color(NSColor.separatorColor)

    // Card background
    static let cardBackground = Color(NSColor.textBackgroundColor)

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

    // Tag Colors
    private static let tagColors: [Color] = [
        Color(red: 0.40, green: 0.65, blue: 0.95),  // Blue
        Color(red: 0.45, green: 0.75, blue: 0.45),  // Green
        Color(red: 0.75, green: 0.55, blue: 0.95),  // Purple
        Color(red: 0.55, green: 0.75, blue: 0.85),  // Light Blue
        Color(red: 0.95, green: 0.78, blue: 0.45),  // Golden Yellow
        Color(red: 0.65, green: 0.45, blue: 0.85),  // Violet
        Color(red: 0.50, green: 0.85, blue: 0.75),  // Teal
        Color(red: 0.45, green: 0.85, blue: 0.65),  // Mint
        Color(red: 0.70, green: 0.60, blue: 0.45),  // Brown
        Color(red: 0.55, green: 0.65, blue: 0.45),  // Sage
    ]

    // Urgency tag colors (priority order: today > thisweek > urgent)
    static let todayTagColor = Color(red: 0.95, green: 0.2, blue: 0.2)      // Bright red for #today
    static let thisWeekTagColor = Color(red: 0.9, green: 0.4, blue: 0.1)    // Orange-red for #thisweek
    static let urgentTagColor = Color(red: 1.0, green: 0.5, blue: 0.0)      // Orange for #urgent

    // Context tag colors
    static let contextTagColors: [String: Color] = [
        "prep": Color(red: 0.4, green: 0.6, blue: 0.9),
        "reply": Color(red: 0.5, green: 0.8, blue: 0.5),
        "deep": Color(red: 0.7, green: 0.5, blue: 0.9),
        "waiting": Color(red: 0.6, green: 0.6, blue: 0.6)
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
        if tagKey == "thisweek" {
            return thisWeekTagColor
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
}
