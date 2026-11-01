import Foundation

/// Reconciles effective AX trust with native event capture, including permission changes
/// after an update. A visible System Settings entry is not proof of effective trust.
@MainActor
final class AccessibilityMonitoringController {
    private let accessibility: any AccessibilityServiceProtocol
    private let monitor: any EventMonitoringProtocol
    private let scheduler: any ActionScheduling
    private let onPermissionChanged: (Bool) -> Void
    private var pending: (any ScheduledAction)?
    private var isRunning = false
    private var generation: UInt64 = 0
    private var lastPermission: Bool?

    init(
        accessibility: any AccessibilityServiceProtocol,
        monitor: any EventMonitoringProtocol,
        scheduler: (any ActionScheduling)? = nil,
        onPermissionChanged: @escaping (Bool) -> Void
    ) {
        self.accessibility = accessibility
        self.monitor = monitor
        self.scheduler = scheduler ?? MainActorScheduler.shared
        self.onPermissionChanged = onPermissionChanged
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reconcile(promptIfNeeded: true)
        scheduleCheck()
    }

    /// Also called on application activation so returning from Settings recovers promptly.
    func refresh() {
        guard isRunning else { return }
        reconcile(promptIfNeeded: false)
    }

    func stop() {
        isRunning = false
        generation &+= 1
        pending?.cancel()
        pending = nil
        lastPermission = nil
        monitor.stopMonitoring()
    }

    private func reconcile(promptIfNeeded: Bool) {
        let granted = accessibility.isAccessibilityGranted(promptIfNeeded: promptIfNeeded)
        if granted {
            // startMonitoring is idempotent while registered. A failed native tap
            // remains unregistered and is retried even if AX trust never changed.
            monitor.startMonitoring()
        } else if lastPermission != false {
            monitor.stopMonitoring()
        }
        if lastPermission != granted {
            lastPermission = granted
            onPermissionChanged(granted)
        }
    }

    private func scheduleCheck() {
        let expected = generation
        pending = scheduler.schedule(after: 2) { [weak self] in
            guard let self, self.isRunning, self.generation == expected else { return }
            self.pending = nil
            self.refresh()
            self.scheduleCheck()
        }
    }
}
