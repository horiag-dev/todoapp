import AppKit
import Carbon.HIToolbox

/// Manages global keyboard shortcuts that work from any app
class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var eventMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    /// Start listening for global hotkeys
    func start() {
        // Monitor for events when app is NOT focused (global)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Also monitor when app IS focused (local) - for consistency
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }
    }

    /// Stop listening for global hotkeys
    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    /// Handle a key event, returns true if handled
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check for ⌘⇧T (Command + Shift + T)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandShift = flags.contains([.command, .shift]) && !flags.contains(.option) && !flags.contains(.control)

        if isCommandShift && event.keyCode == kVK_ANSI_T {
            DispatchQueue.main.async {
                QuickAddWindowController.shared.showQuickAddPanel()
            }
            return true
        }

        return false
    }

    /// Check if the app has accessibility permissions (required for global monitoring)
    static func hasAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Request accessibility permissions (shows system dialog)
    static func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
