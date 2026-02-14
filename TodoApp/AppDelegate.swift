import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply saved appearance
        AppearanceManager.shared.applyAppearance()

        // Start global hotkey monitoring
        setupGlobalHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up
        GlobalHotkeyManager.shared.stop()
    }

    private func setupGlobalHotkey() {
        // Check for accessibility permissions
        if !GlobalHotkeyManager.hasAccessibilityPermissions() {
            // Request permissions - this will show a system dialog
            GlobalHotkeyManager.requestAccessibilityPermissions()
        }

        // Start the global hotkey monitor
        GlobalHotkeyManager.shared.start()
    }
}
