import Cocoa

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared
    private let eventMonitor: EventMonitoringProtocol = GlobalEventMonitor.shared

    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("[MacSnap] Starting application...")

        // Initialize status bar menu
        menuBarController = MenuBarController()

        // Check accessibility permissions on launch
        let hasPermission = accessibilityService.isAccessibilityGranted(promptIfNeeded: true)
        if !hasPermission {
            print("[MacSnap] Accessibility permission pending. Prompt displayed to user.")
        }

        // Start global window dragging and edge snapping monitor
        eventMonitor.startMonitoring()

        // Initial auto-detection of adjacent windows on all connected displays
        PairedResizeManager.shared.autoDetectAdjacentWindows()

        // Observe application switches to auto-connect adjacent windows
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PairedResizeManager.shared.autoDetectAdjacentWindows()
            }
        }

        print("[MacSnap] Ready to manage windows.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        eventMonitor.stopMonitoring()
        print("[MacSnap] Quitting application.")
    }
}
