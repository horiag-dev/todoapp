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
    
    static let urgentTagColor = Color(NSColor(red: 0.90, green: 0.25, blue: 0.20, alpha: 1.0))  // Bright red for urgent/today
    
    // Track used colors and tag assignments
    private static var usedColors: Set<Int> = []
    private static var tagColorMap: [String: Color] = [:]
    
    // Function to get consistent color for a tag
    static func colorForTag(_ tag: String) -> Color {
        let tagKey = tag.lowercased()
        
        // Special tags get red
        if tagKey == "urgent" || tagKey == "today" {
            return urgentTagColor
        }
        
        // Return cached color if already assigned
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
    
    // Gradient backgrounds - using system colors for dark mode support
    static let leftColumnGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(NSColor.controlAccentColor).opacity(0.05),
            Color(NSColor.windowBackgroundColor)
        ]),
        startPoint: .top,
        endPoint: .bottom
    )

    static let middleColumnGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(NSColor.controlAccentColor).opacity(0.05),
            Color(NSColor.windowBackgroundColor)
        ]),
        startPoint: .top,
        endPoint: .bottom
    )

    static let rightColumnGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(NSColor.controlAccentColor).opacity(0.05),
            Color(NSColor.windowBackgroundColor)
        ]),
        startPoint: .top,
        endPoint: .bottom
    )

    // Main continuous background gradient - adapts to dark mode
    static let mainBackgroundGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(NSColor.windowBackgroundColor),
            Color(NSColor.windowBackgroundColor)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
} 