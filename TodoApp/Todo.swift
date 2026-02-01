import Foundation
import SwiftUI

enum Priority: String, Codable, CaseIterable {
    case thisWeek = "This Week"
    case urgent = "Urgent"
    case normal = "Normal"

    var color: Color {
        switch self {
        case .thisWeek: return Color(red: 0.9, green: 0.4, blue: 0.1)  // Orange-red
        case .urgent: return .red
        case .normal: return Theme.accent
        }
    }

    var icon: String {
        switch self {
        case .thisWeek: return "calendar.badge.exclamationmark"
        case .urgent: return "flag.fill"
        case .normal: return "flag"
        }
    }

    var emoji: String {
        switch self {
        case .thisWeek: return "🟠"
        case .urgent: return "🔴"
        case .normal: return "🔵"
        }
    }

    // Support decoding old "When there's time" values as normal
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "When there's time" {
            self = .normal
        } else {
            self = Priority(rawValue: rawValue) ?? .normal
        }
    }
}

struct Todo: Identifiable, Codable, Equatable {
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
    
    init(title: String, isCompleted: Bool = false, tags: [String] = [], priority: Priority = .thisWeek) {
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = Date()
        self.tags = tags
        self.priority = priority
    }
} 