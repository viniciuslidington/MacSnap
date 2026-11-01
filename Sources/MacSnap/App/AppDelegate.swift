import Cocoa

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var appUpdater: (any AppUpdating)?
    private var appUninstaller: AppUninstaller?
    private let accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared
    private let eventMonitor: EventMonitoringProtocol = GlobalEventMonitor.shared
    private var accessibilityMonitoring: AccessibilityMonitoringController?
    private var activationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("[MacSnap] Starting application...")

        // Initialize status bar menu
        let updater = SparkleAppUpdater(installationIsBusy: {
            GlobalEventMonitor.shared.hasActiveWindowInteraction ||
                PairedResizeManager.shared.hasActiveResizeOperation || NSEvent.pressedMouseButtons != 0
        }, mayCheckForUpdates: { [weak self] in self?.appUninstaller?.isPreparing != true })
        appUpdater = updater
        let uninstaller = AppUninstaller(canUninstall: { updater.presentation.isUninstallSafe })
        appUninstaller = uninstaller
        menuBarController = MenuBarController(
            appUpdater: updater,
            onUninstall: uninstaller.isAvailable ? { [weak uninstaller] in uninstaller?.requestUninstall() } : nil
        )

        let accessibilityMonitoring = AccessibilityMonitoringController(
            accessibility: accessibilityService, monitor: eventMonitor,
            onPermissionChanged: { granted in
                if granted {
                    PairedResizeManager.shared.autoDetectAdjacentWindows()
                } else {
                    PairedResizeManager.shared.clearPairing()
                    print("[MacSnap] Effective Accessibility permission is missing. Renew MacSnap's authorization in System Settings; an older build's entry may still be enabled.")
                }
            }
        )
        self.accessibilityMonitoring = accessibilityMonitoring
        accessibilityMonitoring.start()

        // Observe application switches to auto-connect adjacent windows and immediately suppress occluded dividers
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                self?.accessibilityMonitoring?.refresh()
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

        print("[MacSnap] Application started; window monitoring follows effective Accessibility permission.")
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
        accessibilityMonitoring?.stop()
        accessibilityMonitoring = nil
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
