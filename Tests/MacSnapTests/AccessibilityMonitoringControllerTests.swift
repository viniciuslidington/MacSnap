import CoreGraphics
import Foundation
import Testing
@testable import MacSnap

@MainActor
struct AccessibilityMonitoringControllerTests {
    @Test func permissionGrantedAfterLaunchStartsCaptureWithoutRestarting() {
        let f = MonitoringFixture(granted: false)
        f.controller.start()
        #expect(f.monitor.attempts == 0)
        #expect(f.changes.values == [false])
        f.access.granted = true
        f.clock.advance()
        #expect(f.monitor.isActive)
        #expect(f.changes.values == [false, true])
        #expect(f.access.prompts == [true, false])
    }

    @Test func failedTapCreationIsRetriedEvenWhilePermissionRemainsGranted() {
        let f = MonitoringFixture(granted: true)
        f.monitor.failuresRemaining = 2
        f.controller.start()
        #expect(!f.monitor.isActive)
        f.clock.advance()
        #expect(!f.monitor.isActive)
        f.clock.advance()
        #expect(f.monitor.isActive)
        #expect(f.monitor.attempts == 3)
        // Repeated checks do not rediscover pairs or prompt the user repeatedly.
        #expect(f.changes.values == [true])
        #expect(f.access.prompts == [true, false, false])
    }

    @Test func permissionLossStopsCaptureAndRestorationStartsItAgain() {
        let f = MonitoringFixture(granted: true)
        f.controller.start()
        #expect(f.monitor.isActive)
        f.access.granted = false
        f.clock.advance()
        #expect(!f.monitor.isActive)
        #expect(f.monitor.stops == 1)
        f.clock.advance()
        #expect(f.monitor.stops == 1)
        f.access.granted = true
        f.controller.refresh()
        #expect(f.monitor.isActive)
        #expect(f.changes.values == [true, false, true])
    }

    @Test func stoppingRejectsAlreadyQueuedCallbacksIncludingAfterRestart() {
        let f = MonitoringFixture(granted: true)
        f.controller.start()
        f.controller.stop()
        #expect(!f.monitor.isActive)
        let attempts = f.monitor.attempts
        f.controller.refresh()
        #expect(f.monitor.attempts == attempts)
        f.controller.start()
        f.clock.advance(deliverCancelled: true)
        // Only the current lifetime can reconcile or enqueue the next check.
        #expect(f.monitor.attempts == attempts + 2)
        #expect(f.clock.pendingCount == 1)
        f.controller.stop()
        let stoppedAttempts = f.monitor.attempts
        f.clock.advance(deliverCancelled: true)
        #expect(f.monitor.attempts == stoppedAttempts)
        #expect(f.clock.pendingCount == 0)
    }

    @Test func repeatedStartCreatesOnlyOnePollingLoop() {
        let f = MonitoringFixture(granted: true)
        f.controller.start()
        f.controller.start()
        #expect(f.monitor.attempts == 1)
        #expect(f.clock.pendingCount == 1)
        f.clock.advance()
        #expect(f.monitor.attempts == 2)
        #expect(f.clock.pendingCount == 1)
    }
}

@MainActor
private final class MonitoringFixture {
    let access: MonitoringAccess
    let monitor = RecoveringMonitor()
    let clock = MonitoringClock()
    let changes = PermissionChanges()
    let controller: AccessibilityMonitoringController

    init(granted: Bool) {
        access = MonitoringAccess(granted: granted)
        let changes = self.changes
        controller = AccessibilityMonitoringController(
            accessibility: access, monitor: monitor, scheduler: clock,
            onPermissionChanged: { changes.values.append($0) }
        )
    }
}

@MainActor private final class PermissionChanges { var values: [Bool] = [] }

private final class MonitoringAccess: AccessibilityServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedGranted: Bool
    private var storedPrompts: [Bool] = []
    init(granted: Bool) { storedGranted = granted }
    var granted: Bool {
        get { lock.withLock { storedGranted } }
        set { lock.withLock { storedGranted = newValue } }
    }
    var prompts: [Bool] { lock.withLock { storedPrompts } }
    func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool {
        lock.withLock {
            storedPrompts.append(promptIfNeeded)
            return storedGranted
        }
    }
    func getFocusedWindow() -> WindowElement? { nil }
    func getWindowUnderPoint(_ point: CGPoint) -> WindowElement? { nil }
}

@MainActor
private final class RecoveringMonitor: EventMonitoringProtocol {
    var attempts = 0
    var stops = 0
    var failuresRemaining = 0
    var isActive = false
    func startMonitoring() {
        attempts += 1
        if failuresRemaining > 0 { failuresRemaining -= 1; return }
        isActive = true
    }
    func stopMonitoring() { stops += 1; isActive = false }
}

@MainActor
private final class MonitoringClock: ActionScheduling {
    private var pending: [MonitoringAction] = []
    var pendingCount: Int { pending.count }
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledAction {
        let job = MonitoringAction(action: action)
        pending.append(job)
        return job
    }
    func advance(deliverCancelled: Bool = false) {
        let jobs = pending
        pending.removeAll()
        for job in jobs where deliverCancelled || !job.cancelled { job.action() }
    }
}

@MainActor
private final class MonitoringAction: ScheduledAction {
    let action: @MainActor () -> Void
    var cancelled = false
    init(action: @escaping @MainActor () -> Void) { self.action = action }
    func cancel() { cancelled = true }
}
