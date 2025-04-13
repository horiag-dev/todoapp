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
    private static let tagColors: [Color] = [
        Color(NSColor(red: 0.40, green: 0.65, blue: 0.95, alpha: 1.0)),  // Blue
        Color(NSColor(red: 0.45, green: 0.75, blue: 0.45, alpha: 1.0)),  // Green
        Color(NSColor(red: 0.75, green: 0.55, blue: 0.95, alpha: 1.0)),  // Purple
        Color(NSColor(red: 0.55, green: 0.75, blue: 0.85, alpha: 1.0)),  // Light Blue
        Color(NSColor(red: 0.95, green: 0.65, blue: 0.45, alpha: 1.0)),  // Orange
        Color(NSColor(red: 0.65, green: 0.45, blue: 0.85, alpha: 1.0)),  // Violet
        Color(NSColor(red: 0.85, green: 0.75, blue: 0.35, alpha: 1.0)),  // Yellow
        Color(NSColor(red: 0.85, green: 0.55, blue: 0.75, alpha: 1.0)),  // Pink
        Color(NSColor(red: 0.50, green: 0.85, blue: 0.75, alpha: 1.0)),  // Teal
        Color(NSColor(red: 0.95, green: 0.45, blue: 0.50, alpha: 1.0)),  // Coral
        Color(NSColor(red: 0.70, green: 0.60, blue: 0.45, alpha: 1.0)),  // Brown
        Color(NSColor(red: 0.45, green: 0.60, blue: 0.70, alpha: 1.0)),  // Steel Blue
        Color(NSColor(red: 0.75, green: 0.45, blue: 0.45, alpha: 1.0)),  // Burgundy
        Color(NSColor(red: 0.45, green: 0.75, blue: 0.65, alpha: 1.0)),  // Mint
        Color(NSColor(red: 0.65, green: 0.45, blue: 0.65, alpha: 1.0)),  // Plum
        Color(NSColor(red: 0.55, green: 0.65, blue: 0.45, alpha: 1.0)),  // Olive
        Color(NSColor(red: 0.85, green: 0.45, blue: 0.85, alpha: 1.0)),  // Magenta
        Color(NSColor(red: 0.45, green: 0.85, blue: 0.85, alpha: 1.0)),  // Cyan
        Color(NSColor(red: 0.75, green: 0.65, blue: 0.55, alpha: 1.0)),  // Tan
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