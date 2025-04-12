import Foundation
import SwiftUI

enum Priority: String, Codable, CaseIterable {
    case urgent = "Urgent"
    case normal = "Normal"
    case whenTime = "When there's time"
    
    var color: Color {
        switch self {
        case .urgent: return .red
        case .normal: return .blue
        case .whenTime: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .urgent: return "exclamationmark.triangle.fill"
        case .normal: return "circle.fill"
        case .whenTime: return "clock.fill"
        }
    }
}

struct Todo: Identifiable, Codable {
    var id = UUID()
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    var tags: [String]
    var priority: Priority
    
    init(title: String, isCompleted: Bool = false, tags: [String] = [], priority: Priority = .normal) {
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = Date()
        self.tags = tags
        self.priority = priority
    }
} 