import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import MacSnap

@MainActor
@Suite(.serialized)
struct SnapEngineTests {
    @Test func exactAndAdaptiveIntentsUseTheSamePolicyForPreviewAndPlacement() throws {
        let f = try Fixture()
        defer { f.manager.clearPairing() }
        let bounds = f.screen.visibleFrame
        let neighbor = f.window(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width * 0.65, height: bounds.height))
        let moving = f.window(bounds)
        f.discovery.windows = [neighbor.0]
        let exact = f.engine.previewRect(for: moving.0, to: .rightHalf, on: f.screen, forceExactSize: true)
        #expect(exact == SnapZone.rightHalf.targetRect(for: bounds))
        f.engine.snapWindow(moving.0, to: .rightHalf, on: f.screen, forceExactSize: true)
        #expect(moving.0.cocoaFrame(primaryScreenHeight: f.height) == exact)
        #expect(f.manager.state(for: f.screen).pair == nil)

        let adaptive = f.engine.previewRect(for: moving.0, to: .rightHalf, on: f.screen, forceExactSize: false)
        #expect(abs(adaptive.minX - (bounds.minX + bounds.width * 0.65)) < 0.001)
        f.engine.snapWindow(moving.0, to: .rightHalf, on: f.screen)
        #expect(moving.0.cocoaFrame(primaryScreenHeight: f.height) == adaptive)
        let pair = try #require(f.manager.state(for: f.screen).pair)
        #expect(pair.firstWindow.isSameWindow(as: neighbor.0))
        #expect(pair.secondWindow.isSameWindow(as: moving.0))
    }

    @Test func placementRefreshesObservationsAndFailedWritesDoNotRegister() throws {
        let f = try Fixture()
        defer { f.manager.clearPairing() }
        let bounds = f.screen.visibleFrame
        let neighbor = f.window(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width * 0.65, height: bounds.height))
        let moving = f.window(bounds)
        f.discovery.windows = [neighbor.0]
        let before = f.engine.previewRect(for: moving.0, to: .rightHalf, on: f.screen, forceExactSize: false)
        let updated = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width * 0.55, height: bounds.height)
        _ = neighbor.0.setCocoaFrame(updated, primaryScreenHeight: f.height)
        f.engine.snapWindow(moving.0, to: .rightHalf, on: f.screen)
        let placed = try #require(moving.0.cocoaFrame(primaryScreenHeight: f.height))
        #expect(placed != before)
        #expect(abs(placed.minX - updated.maxX) < 0.001)

        f.manager.clearPairing()
        moving.1.rejectWrites = true
        let snapshotCount = f.discovery.snapshotCount
        f.engine.snapWindow(moving.0, to: .leftHalf, on: f.screen, forceExactSize: true)
        #expect(f.discovery.snapshotCount == snapshotCount)
        #expect(f.manager.activePairs.isEmpty)
    }

    @Test func threeColumnsAreNotConvertedToABinaryPair() throws {
        let f = try Fixture()
        defer { f.manager.clearPairing() }
        let bounds = f.screen.visibleFrame
        let left = f.window(SnapZone.leftThird.targetRect(for: bounds))
        let center = f.window(bounds)
        let right = f.window(SnapZone.rightThird.targetRect(for: bounds))
        f.discovery.windows = [left.0, center.0, right.0]
        f.engine.snapWindow(center.0, to: .centerThird, on: f.screen, forceExactSize: true)
        #expect(center.0.cocoaFrame(primaryScreenHeight: f.height) == SnapZone.centerThird.targetRect(for: bounds))
        #expect(f.manager.autoDetectAdjacentWindows(on: f.screen).isEmpty)
        #expect(f.manager.activePairs.isEmpty)
        #expect(left.1.writes == 0 && right.1.writes == 0)
    }

    @Test func cancelledDropCannotPlaceOrRediscoverEvenIfSchedulerDeliversIt() throws {
        let f = try Fixture()
        defer { f.manager.clearPairing() }
        let moving = f.window(f.screen.visibleFrame)
        f.engine.completeDrag(window: moving.0, zone: .leftHalf, screen: f.screen, forceExactSize: true)
        #expect(moving.1.writes == 0)
        f.engine.cancelPendingOperations()
        f.clock.deliverAllIncludingCancelled()
        #expect(moving.1.writes == 0)
        #expect(f.discovery.snapshotCount == 0)

        f.engine.completeDrag(window: moving.0, zone: .rightHalf, screen: f.screen, forceExactSize: true)
        f.clock.deliverAllIncludingCancelled()
        #expect(moving.1.writes == 1)
        #expect(moving.0.cocoaFrame(primaryScreenHeight: f.height) == SnapZone.rightHalf.targetRect(for: f.screen.visibleFrame))
        f.clock.deliverAllIncludingCancelled()
        #expect(f.discovery.snapshotCount >= 1)
    }

    @Test func disconnectedDisplayCancelsDeferredPlacementAndDiscovery() throws {
        let f = try Fixture()
        defer { f.manager.clearPairing() }
        let moving = f.window(f.screen.visibleFrame)
        f.engine.completeDrag(window: moving.0, zone: .leftHalf, screen: f.screen, forceExactSize: true)
        f.screens.screens = []
        f.clock.deliverAllIncludingCancelled()
        f.clock.deliverAllIncludingCancelled()
        #expect(moving.1.writes == 0)
        #expect(f.discovery.snapshotCount == 0)
    }

    @Test func explicitSnapSupersedesADelayedDrop() throws {
        let f = try Fixture()
        defer { f.manager.clearPairing() }
        let moving = f.window(f.screen.visibleFrame)
        f.engine.completeDrag(window: moving.0, zone: .leftHalf, screen: f.screen, forceExactSize: true)
        f.engine.snapWindow(moving.0, to: .rightHalf, on: f.screen, forceExactSize: true)
        f.clock.deliverAllIncludingCancelled()
        #expect(moving.1.writes == 1)
        #expect(moving.0.cocoaFrame(primaryScreenHeight: f.height) == SnapZone.rightHalf.targetRect(for: f.screen.visibleFrame))
    }

    @Test func pairAdmissionRejectsPartialRowsAndThreeColumnsButAcceptsBothAxes() {
        let frame = CGRect(x: -1920, y: 50, width: 1920, height: 1000)
        #expect(PairGeometry.split(first: SnapZone.leftHalf.targetRect(for: frame), second: SnapZone.rightHalf.targetRect(for: frame), in: frame)?.orientation == .horizontal)
        #expect(PairGeometry.split(first: SnapZone.topHalf.targetRect(for: frame), second: SnapZone.bottomHalf.targetRect(for: frame), in: frame)?.orientation == .vertical)
        #expect(PairGeometry.split(first: SnapZone.topLeftQuarter.targetRect(for: frame), second: SnapZone.topRightQuarter.targetRect(for: frame), in: frame) == nil)
        #expect(PairGeometry.split(first: SnapZone.leftThird.targetRect(for: frame), second: SnapZone.centerThird.targetRect(for: frame), in: frame) == nil)
        #expect(PairGeometry.split(first: .zero, second: frame, in: frame) == nil)
        let oddFrame = CGRect(x: 0, y: 0, width: 1001, height: 1000)
        let roundedFirst = CGRect(x: 0, y: 0, width: 150, height: 1000)
        let roundedSecond = CGRect(x: 150, y: 0, width: 851, height: 1000)
        #expect(PairGeometry.split(first: roundedFirst, second: roundedSecond, in: oddFrame)?.ratio == 0.15)
    }
}

@MainActor
private final class Fixture {
    let screen: NSScreen
    let height: CGFloat
    let screens: SnapScreens
    let discovery: SnapScene
    let manager: PairedResizeManager
    let clock = SnapClock()
    let engine: SnapEngine

    init() throws {
        _ = NSApplication.shared
        screen = try #require(NSScreen.screens.first)
        height = screen.frame.height
        screens = SnapScreens(screen: screen)
        discovery = SnapScene(primaryHeight: height)
        manager = PairedResizeManager(screenService: screens, windowDiscovery: discovery, isMasterEnabled: { true })
        engine = SnapEngine(screenService: screens, pairingManager: manager, discovery: discovery, scheduler: clock)
    }

    func window(_ cocoa: CGRect) -> (WindowElement, SnapFrames) {
        let access = SnapFrames(ScreenGeometry.cocoaToAX(cocoaRect: cocoa, primaryScreenHeight: height))
        let window = WindowElement(element: AXUIElementCreateSystemWide(), pid: 9021, frameAccess: access, identity: UUID())
        return (window, access)
    }
}

/// The lock protects every mutable field used by this scripted Sendable adapter.
private final class SnapFrames: WindowFrameAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CGRect
    private var rejected = false
    private var count = 0
    init(_ frame: CGRect) { stored = frame }
    var frame: CGRect? { lock.withLock { stored } }
    var isResizable: Bool { true }
    var writes: Int { lock.withLock { count } }
    var rejectWrites: Bool {
        get { lock.withLock { rejected } }
        set { lock.withLock { rejected = newValue } }
    }
    func setFrame(_ frame: CGRect) -> Bool {
        lock.withLock {
            count += 1
            guard !rejected else { return false }
            stored = frame
            return true
        }
    }
}

@MainActor
private final class SnapScene: WindowDiscovering {
    let primaryHeight: CGFloat
    var windows: [WindowElement] = []
    var snapshotCount = 0
    init(primaryHeight: CGFloat) { self.primaryHeight = primaryHeight }
    func snapshot(primaryScreenHeight: CGFloat) -> WindowSnapshot? {
        snapshotCount += 1
        let records = windows.enumerated().compactMap { index, window -> WindowObservation? in
            guard let frame = window.cocoaFrame(primaryScreenHeight: primaryScreenHeight) else { return nil }
            return WindowObservation(windowID: CGWindowID(index + 1), pid: window.pid, frame: frame)
        }
        let captured = windows
        return WindowSnapshot(windows: records) { record in captured[Int(record.windowID) - 1] }
    }
    func window(atCocoaPoint point: CGPoint, excluding: WindowElement?, primaryScreenHeight: CGFloat) -> WindowElement? {
        windows.first { candidate in
            (excluding.map { !candidate.isSameWindow(as: $0) } ?? true) && candidate.cocoaFrame(primaryScreenHeight: primaryScreenHeight)?.contains(point) == true
        }
    }
}

@MainActor
private final class SnapClock: ActionScheduling {
    private var jobs: [@MainActor () -> Void] = []
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledAction {
        jobs.append(action)
        return SnapCancellation()
    }
    func deliverAllIncludingCancelled() {
        let current = jobs
        jobs.removeAll()
        current.forEach { $0() }
    }
}
@MainActor private final class SnapCancellation: ScheduledAction { func cancel() {} }

// Main-actor test code mutates this adapter; synchronization satisfies the existing Sendable screen contract.
private final class SnapScreens: ScreenServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var connected: [NSScreen]
    private let height: CGFloat
    init(screen: NSScreen) { connected = [screen]; height = screen.frame.height }
    var screens: [NSScreen] {
        get { lock.withLock { connected } }
        set { lock.withLock { connected = newValue } }
    }
    var primaryScreen: NSScreen? { screens.first }
    var primaryScreenHeight: CGFloat { height }
    func screenContaining(point: CGPoint) -> NSScreen? { screens.first { $0.frame.contains(point) } }
    func screenContaining(rect: CGRect) -> NSScreen? { screens.first { $0.frame.intersects(rect) } }
}
