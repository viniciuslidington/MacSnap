import Cocoa

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var appUpdater: (any AppUpdating)?
    private let accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared
    private let eventMonitor: EventMonitoringProtocol = GlobalEventMonitor.shared
    private var activationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("[MacSnap] Starting application...")

        // Initialize status bar menu
        let updater = SparkleAppUpdater(installationIsBusy: {
            GlobalEventMonitor.shared.hasActiveWindowInteraction ||
                PairedResizeManager.shared.hasActiveResizeOperation || NSEvent.pressedMouseButtons != 0
        })
        appUpdater = updater
        menuBarController = MenuBarController(appUpdater: updater)

        // Check accessibility permissions on launch
        let hasPermission = accessibilityService.isAccessibilityGranted(promptIfNeeded: true)
        if !hasPermission {
            print("[MacSnap] Accessibility permission pending. Prompt displayed to user.")
        }

        // Start global window dragging and edge snapping monitor
        eventMonitor.startMonitoring()

        // Initial auto-detection of adjacent windows on all connected displays
        PairedResizeManager.shared.autoDetectAdjacentWindows()

        // Observe application switches to auto-connect adjacent windows and immediately suppress occluded dividers
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                PairedResizeManager.shared.handleApplicationActivated(app)
                PairedResizeManager.shared.autoDetectAdjacentWindows()
            }
        }

        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in PairedResizeManager.shared.handleScreenConfigurationChange() }
        }

        print("[MacSnap] Ready to manage windows.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        eventMonitor.stopMonitoring()
        PairedResizeManager.shared.clearPairing()
        print("[MacSnap] Quitting application.")
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if appUpdater?.deferTermination(resume: {
            sender.reply(toApplicationShouldTerminate: true)
        }) == true { return .terminateLater }
        return .terminateNow
    }
}
