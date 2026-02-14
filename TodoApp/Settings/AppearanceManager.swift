import SwiftUI
import AppKit

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

/// Manages the app's appearance (light/dark mode)
class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    private let userDefaultsKey = "appearanceMode"

    @Published var currentMode: AppearanceMode {
        didSet {
            saveMode()
            applyAppearance()
        }
    }

    private init() {
        // Load saved preference
        if let savedMode = UserDefaults.standard.string(forKey: userDefaultsKey),
           let mode = AppearanceMode(rawValue: savedMode) {
            self.currentMode = mode
        } else {
            self.currentMode = .system
        }

        // Apply on init
        applyAppearance()
    }

    private func saveMode() {
        UserDefaults.standard.set(currentMode.rawValue, forKey: userDefaultsKey)
    }

    func applyAppearance() {
        DispatchQueue.main.async {
            switch self.currentMode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
}
