import SwiftUI

/// A configurable context category for grouping todos
struct ContextConfig: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String
    var colorHex: String

    var color: Color {
        Color(hex: colorHex) ?? .gray
    }

    init(id: String, name: String, icon: String, color: Color) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = color.toHex() ?? "#808080"
    }

    init(id: String, name: String, icon: String, colorHex: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
    }
}

/// Manages configurable context categories
class ContextConfigManager: ObservableObject {
    static let shared = ContextConfigManager()

    @Published var contexts: [ContextConfig] {
        didSet {
            saveContexts()
        }
    }

    private let userDefaultsKey = "contextConfigurations"

    // Default contexts
    static let defaultContexts: [ContextConfig] = [
        ContextConfig(id: "prep", name: "Prep", icon: "calendar", color: Color(red: 0.4, green: 0.6, blue: 0.9)),
        ContextConfig(id: "reply", name: "Reply", icon: "arrowshape.turn.up.left.fill", color: Color(red: 0.5, green: 0.8, blue: 0.5)),
        ContextConfig(id: "deep", name: "Deep", icon: "brain.head.profile", color: Color(red: 0.7, green: 0.5, blue: 0.9)),
        ContextConfig(id: "waiting", name: "Waiting", icon: "hourglass", color: Color(red: 0.6, green: 0.6, blue: 0.6))
    ]

    private init() {
        self.contexts = Self.defaultContexts
        loadContexts()
    }

    var contextTags: [String] {
        contexts.map { $0.id.lowercased() }
    }

    func context(for tag: String) -> ContextConfig? {
        contexts.first { $0.id.lowercased() == tag.lowercased() }
    }

    func color(for tag: String) -> Color {
        context(for: tag)?.color ?? Theme.colorForTag(tag)
    }

    func icon(for tag: String) -> String {
        context(for: tag)?.icon ?? "tag"
    }

    func addContext(_ context: ContextConfig) {
        contexts.append(context)
    }

    func removeContext(at index: Int) {
        guard index < contexts.count else { return }
        contexts.remove(at: index)
    }

    func updateContext(_ context: ContextConfig) {
        if let index = contexts.firstIndex(where: { $0.id == context.id }) {
            contexts[index] = context
        }
    }

    func resetToDefaults() {
        contexts = Self.defaultContexts
    }

    private func saveContexts() {
        if let encoded = try? JSONEncoder().encode(contexts) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    private func loadContexts() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([ContextConfig].self, from: data) {
            self.contexts = decoded
        }
    }
}

// MARK: - Color Extensions for Hex Conversion

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
