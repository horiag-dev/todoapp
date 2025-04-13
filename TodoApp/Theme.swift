import SwiftUI

enum Theme {
    // Colors
    static let background = Color(.windowBackgroundColor)
    static let secondaryBackground = Color(NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0))
    static let accent = Color(NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)) // Things blue
    static let text = Color.primary
    static let secondaryText = Color(NSColor.secondaryLabelColor)
    static let divider = Color(NSColor.separatorColor)
    
    // Font sizes
    static let titleFont: Font = .title2.bold()
    static let headlineFont: Font = .headline
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let smallFont = Font.system(size: 11, weight: .regular)
    
    // Spacing
    static let itemSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 24
    static let contentPadding: CGFloat = 16
    
    // Corners
    static let cornerRadius: CGFloat = 6
    
    // Updated Tag Colors - More like Things3
    static let tagColors: [Color] = [
        Color(NSColor(red: 0.40, green: 0.65, blue: 0.95, alpha: 1.0)),  // Blue
        Color(NSColor(red: 0.45, green: 0.75, blue: 0.45, alpha: 1.0)),  // Green
        Color(NSColor(red: 0.75, green: 0.55, blue: 0.95, alpha: 1.0)),  // Purple
        Color(NSColor(red: 0.55, green: 0.75, blue: 0.85, alpha: 1.0)),  // Light Blue
        Color(NSColor(red: 0.95, green: 0.65, blue: 0.45, alpha: 1.0)),  // Orange
        Color(NSColor(red: 0.65, green: 0.45, blue: 0.85, alpha: 1.0)),  // Violet
        Color(NSColor(red: 0.75, green: 0.75, blue: 0.45, alpha: 1.0)),  // Yellow
        Color(NSColor(red: 0.85, green: 0.55, blue: 0.75, alpha: 1.0))   // Pink
    ]
    
    static let urgentTagColor = Color(NSColor(red: 0.90, green: 0.25, blue: 0.20, alpha: 1.0))  // Bright red for urgent/today
    
    // Function to get consistent color for a tag
    static func colorForTag(_ tag: String) -> Color {
        // Special tags get red
        if tag.lowercased() == "urgent" || tag.lowercased() == "today" {
            return urgentTagColor
        }
        
        // Generate a consistent index based on the tag string
        var hash = 0
        for char in tag.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(char.value)
        }
        return tagColors[abs(hash) % tagColors.count]
    }
    
    // Gradient backgrounds
    static let leftColumnGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color.blue.opacity(0.08),
            Color.white.opacity(0.95)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let middleColumnGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color.blue.opacity(0.08),
            Color.white.opacity(0.95)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let rightColumnGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color.blue.opacity(0.08),
            Color.white.opacity(0.95)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
} 