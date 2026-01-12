import Foundation
import SwiftUI

enum Priority: String, Codable, CaseIterable {
    case urgent = "Urgent"
    case normal = "Normal"
    case whenTime = "When there's time"
    
    var color: Color {
        switch self {
        case .urgent: return .red
        case .normal: return Theme.accent
        case .whenTime: return Theme.secondaryText
        }
    }
    
    var icon: String {
        switch self {
        case .urgent: return "flag.fill"
        case .normal: return "flag"
        case .whenTime: return "clock.fill"
        }
    }
}

struct Todo: Identifiable, Codable {
    // Static cached NSDataDetector for link detection (expensive to create)
    private static let linkDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    var id = UUID()
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    var tags: [String]
    var priority: Priority

    // Add computed property to detect links (uses cached detector)
    var containsLinks: Bool {
        let matches = Self.linkDetector?.matches(in: title, options: [], range: NSRange(location: 0, length: title.utf16.count))
        return (matches?.count ?? 0) > 0
    }
    
    init(title: String, isCompleted: Bool = false, tags: [String] = [], priority: Priority = .normal) {
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = Date()
        self.tags = tags
        self.priority = priority
    }
} 