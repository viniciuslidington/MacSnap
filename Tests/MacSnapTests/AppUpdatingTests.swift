import AppKit
import Testing
@testable import MacSnap

@MainActor
@Suite(.serialized)
struct AppUpdatingTests {
    @Test func menuChecksForUpdatesEvenWhenSnappingIsPaused() throws {
        let updates = ControlledUpdates()
        let monitor = GlobalEventMonitor()
        let saved = UserDefaults.standard.object(forKey: "MacSnap.isMasterEnabled")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "MacSnap.isMasterEnabled") }
            else { UserDefaults.standard.removeObject(forKey: "MacSnap.isMasterEnabled") }
        }
        monitor.isMasterEnabled = false
        let controller = MenuBarController(eventMonitor: monitor, appUpdater: updates)
        let item = try #require(controller.statusItem)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let menu = try #require(item.menu)
        controller.menuWillOpen(menu)
        let check = try #require(menu.item(withTitle: "Check for Updates…"))
        #expect(check.isEnabled)
        menu.performActionForItem(at: menu.index(of: check))
        #expect(updates.checkRequested)
        updates.checkRequested = false
        updates.presentation.canCheck = false
        updates.onChange?()
        #expect(!check.isEnabled)
        menu.performActionForItem(at: menu.index(of: check))
        #expect(!updates.checkRequested)
    }

    @Test func pendingUpdateAndPreferencesArePresentedThroughTheMenu() throws {
        let updates = ControlledUpdates()
        let controller = MenuBarController(appUpdater: updates)
        let item = try #require(controller.statusItem)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let menu = try #require(item.menu)
        let submenu = try #require(menu.item(withTitle: "Updates")?.submenu)
        let checks = try #require(submenu.item(withTitle: "Automatically Check for Updates"))
        let installs = try #require(submenu.item(withTitle: "Automatically Download and Install"))
        #expect(checks.state == .off)
        #expect(installs.state == .off)
        submenu.performActionForItem(at: submenu.index(of: checks))
        #expect(updates.automaticallyChecksForUpdates)
        #expect(!updates.automaticallyInstallsUpdates)
        submenu.performActionForItem(at: submenu.index(of: installs))
        #expect(updates.automaticallyInstallsUpdates)
        updates.presentation.pendingVersion = "1.2.3"
        updates.onChange?()
        #expect(menu.item(withTitle: "Update to 1.2.3…") != nil)
        updates.presentation.pendingVersion = nil
        updates.onChange?()
        #expect(menu.item(withTitle: "Check for Updates…") != nil)
    }

    @Test func unconfiguredBuildDoesNotEnableUpdates() throws {
        let updater = SparkleAppUpdater(installationIsBusy: { false })
        #expect(!updater.presentation.isAvailable)
        #expect(!updater.presentation.canCheck)
        updater.checkForUpdates()
        let controller = MenuBarController(appUpdater: updater)
        let item = try #require(controller.statusItem)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let menu = try #require(item.menu)
        #expect(menu.item(withTitle: "Check for Updates…")?.isEnabled == false)
    }

    @Test func terminationWaitsUntilTheWindowInteractionHasFinished() {
        let scheduler = UpdateTestScheduler()
        var busy = true
        let updater = SparkleAppUpdater(installationIsBusy: { busy }, scheduler: scheduler)
        var resumed = false
        #expect(updater.deferTermination { resumed = true })
        scheduler.advance()
        #expect(!resumed)
        busy = false
        scheduler.advance()
        #expect(resumed)
        resumed = false
        scheduler.advance()
        #expect(!resumed)
        #expect(!updater.deferTermination { resumed = true })
        #expect(!resumed)
    }

    @Test func cancelledTerminationWorkCannotReplyToAnEarlierRequest() {
        let scheduler = UpdateTestScheduler()
        var busy = true
        let updater = SparkleAppUpdater(installationIsBusy: { busy }, scheduler: scheduler)
        var oldReply = false
        var currentReply = false
        #expect(updater.deferTermination { oldReply = true })
        busy = false
        #expect(!updater.deferTermination {})
        busy = true
        #expect(updater.deferTermination { currentReply = true })
        scheduler.advance(deliverCancelled: true)
        busy = false
        scheduler.advance(deliverCancelled: true)
        #expect(!oldReply)
        #expect(currentReply)
    }
}

@MainActor
private final class ControlledUpdates: AppUpdating {
    var presentation = UpdatePresentation(isAvailable: true, canCheck: true)
    var automaticallyChecksForUpdates = false { didSet { onChange?() } }
    var automaticallyInstallsUpdates = false { didSet { onChange?() } }
    var onChange: (() -> Void)?
    var checkRequested = false
    func checkForUpdates() { checkRequested = true }
    func deferTermination(resume: @escaping () -> Void) -> Bool { false }
}

@MainActor
private final class UpdateTestScheduler: ActionScheduling {
    private var pending: [UpdateTestAction] = []
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledAction {
        let task = UpdateTestAction(action: action)
        pending.append(task)
        return task
    }
    func advance(deliverCancelled: Bool = false) {
        let current = pending
        pending = []
        for task in current where deliverCancelled || !task.cancelled { task.action() }
    }
}

@MainActor
private final class UpdateTestAction: ScheduledAction {
    let action: @MainActor () -> Void
    var cancelled = false
    init(action: @escaping @MainActor () -> Void) { self.action = action }
    func cancel() { cancelled = true }
}
