import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import MacSnap

@MainActor
@Suite(.serialized)
struct SnapEngineTests {
    @Test func runnerGeometryPreservesUnconstrainedThirdExactly() throws {
        let bounds = CGRect(x: 0, y: 62, width: 1024, height: 681)
        let target = SnapZone.centerThird.targetRect(for: bounds)
        #expect(WindowSizeLimits().fitting(target, within: bounds) == target)
    }

    @Test func runnerGeometryConstrainedPlacementMatchesPreview() throws {
        let preview = CGRect(x: 409.6, y: 266.29999999999995, width: 614.4, height: 272.40000000000003)
        let access = SnapFrames(.zero)
        let window = WindowElement(element: AXUIElementCreateSystemWide(), pid: 9021, frameAccess: access, identity: UUID())
        #expect(window.setCocoaFrame(preview, primaryScreenHeight: 768))
        try expectFramesClose(window.cocoaFrame(primaryScreenHeight: 768), preview)
    }

    @Test(arguments: [SnapZone.leftHalf, .rightHalf, .topLeftQuarter, .bottomRightQuarter, .maximize, .centerThird])
    func constrainedPreviewMatchesPlacementAndStaysInsideScreen(zone: SnapZone) throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let b = f.screen.visibleFrame
        let moving = f.window(b)
        let fixed = CGSize(width: b.width * 0.6, height: b.height * 0.4)
        moving.1.sizeLimits = .init(minimum: fixed, maximum: fixed)
        let preview = try #require(f.engine.previewRect(for: moving.0, to: zone, on: f.screen, forceExactSize: true))
        #expect(preview.size == fixed)
        #expect(b.contains(preview))
        if zone == .rightHalf || zone == .bottomRightQuarter { #expect(preview.maxX == b.maxX) }
        if zone == .leftHalf || zone == .topLeftQuarter { #expect(preview.minX == b.minX) }
        if zone == .topLeftQuarter { #expect(preview.maxY == b.maxY) }
        if zone == .bottomRightQuarter { #expect(preview.minY == b.minY) }
        f.engine.snapWindow(moving.0, to: zone, on: f.screen, forceExactSize: true)
        try expectFramesClose(moving.0.cocoaFrame(primaryScreenHeight: f.height), preview)
    }

    @Test func unknownLimitsPreserveDefaultPreviewAndDrop() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let moving = f.window(f.screen.visibleFrame)
        moving.1.sizeLimits = .init()
        #expect(f.engine.previewRect(for: moving.0, to: .leftHalf, on: f.screen, forceExactSize: true) == SnapZone.leftHalf.targetRect(for: f.screen.visibleFrame))
        #expect(moving.1.writes == 0) // Preview never probes by resizing a real window.
        f.engine.snapWindow(moving.0, to: .leftHalf, on: f.screen, forceExactSize: true)
        #expect(moving.1.writes == 1)
    }

    @Test func partialBoundsAdjustBothPreviewAndPlacement() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let b = f.screen.visibleFrame
        let moving = f.window(b)
        moving.1.sizeLimits = .init(minimum: CGSize(width: b.width * 0.7, height: 1))
        let preview = try #require(f.engine.previewRect(for: moving.0, to: .rightHalf, on: f.screen, forceExactSize: true))
        f.engine.snapWindow(moving.0, to: .rightHalf, on: f.screen, forceExactSize: true)
        let placed = try #require(moving.0.cocoaFrame(primaryScreenHeight: f.height))
        try expectFramesClose(placed, preview)
        #expect(abs(placed.width - b.width * 0.7) < 0.001)
        #expect(abs(placed.maxX - b.maxX) < 0.001)
    }

    @Test func dropRefreshesLimitsAfterPreviewWithoutResizingDuringPreview() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let b = f.screen.visibleFrame
        let moving = f.window(b)
        let before = f.engine.previewRect(for: moving.0, to: .rightHalf, on: f.screen, forceExactSize: true)
        #expect(moving.1.writes == 0)
        f.engine.completeDrag(window: moving.0, zone: .rightHalf, screen: f.screen, forceExactSize: true)
        let updated = CGSize(width: b.width * 0.6, height: b.height * 0.5)
        moving.1.sizeLimits = .init(minimum: updated, maximum: updated)
        f.clock.deliverAllIncludingCancelled()
        let placed = try #require(moving.0.cocoaFrame(primaryScreenHeight: f.height))
        #expect(placed != before)
        #expect(placed.size == updated)
        #expect(placed.maxX == b.maxX)
    }

    @Test func impossibleBoundsSuppressPreviewAndPlacement() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let b = f.screen.visibleFrame
        let moving = f.window(b)
        moving.1.sizeLimits = .init(minimum: CGSize(width: b.width + 10, height: 10),
                                  maximum: CGSize(width: b.width + 100, height: b.height))
        #expect(f.engine.previewRect(for: moving.0, to: .maximize, on: f.screen, forceExactSize: true) == nil)
        f.engine.snapWindow(moving.0, to: .maximize, on: f.screen, forceExactSize: true)
        #expect(moving.1.writes == 0)
    }

    @Test func invalidBoundsCannotProduceAPreviewOrTarget() {
        let b = CGRect(x: -1200, y: 100, width: 1200, height: 800)
        let invalid: [WindowSizeLimits] = [
            .init(minimum: CGSize(width: -1, height: 10)),
            .init(maximum: .zero),
            .init(maximum: CGSize(width: CGFloat.nan, height: 100)),
            .init(minimum: CGSize(width: 500, height: 100), maximum: CGSize(width: 400, height: 200))
        ]
        for limits in invalid {
            #expect(limits.fitting(b, within: b) == nil)
        }
    }

    @Test func fullScreenWindowRejectsSnappingEvenWhenAXSizeIsSettable() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let moving = f.window(f.screen.visibleFrame)
        moving.1.isFullScreen = true

        #expect(!moving.0.isResizable)
        #expect(!moving.0.setAXFrame(CGRect(x: 0, y: 0, width: 600, height: 500)))
        f.engine.snapWindow(moving.0, to: .leftHalf, on: f.screen, forceExactSize: true)
        f.engine.completeDrag(window: moving.0, zone: .leftHalf, screen: f.screen, forceExactSize: true)
        f.clock.deliverAllIncludingCancelled()
        f.clock.deliverAllIncludingCancelled()

        #expect(moving.1.writes == 0)
        #expect(f.discovery.snapshotCount == 0)
        #expect(f.manager.activePairs.isEmpty)

        moving.1.isFullScreen = false
        f.engine.snapWindow(moving.0, to: .leftHalf, on: f.screen, forceExactSize: true)
        #expect(moving.1.writes == 1)
    }

    @Test func enteringFullScreenBeforeDeferredDropPreventsPlacement() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let moving = f.window(f.screen.visibleFrame)
        f.engine.completeDrag(window: moving.0, zone: .leftHalf, screen: f.screen, forceExactSize: true)
        moving.1.isFullScreen = true
        f.clock.deliverAllIncludingCancelled()
        f.clock.deliverAllIncludingCancelled()

        #expect(moving.1.writes == 0)
        #expect(f.discovery.snapshotCount == 0)
        #expect(f.manager.activePairs.isEmpty)
    }

    @Test func nonResizableWindowRejectsBothFrameAPIsAndSnapping() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let moving = f.window(f.screen.visibleFrame)
        moving.1.isResizable = false
        #expect(!moving.0.setAXFrame(CGRect(x: 0, y: 0, width: 600, height: 500)))
        #expect(!moving.0.setCocoaFrame(f.screen.visibleFrame, primaryScreenHeight: f.height))
        f.engine.snapWindow(moving.0, to: .leftHalf, on: f.screen, forceExactSize: true)
        #expect(moving.1.writes == 0)
        #expect(f.discovery.snapshotCount == 0)
    }

    @Test(arguments: [false, true])
    func fullScreenMemberInvalidatesPairAndPreventsRediscovery(firstIsFullScreen: Bool) throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let first = f.window(SnapZone.leftHalf.targetRect(for: f.screen.visibleFrame))
        let second = f.window(SnapZone.rightHalf.targetRect(for: f.screen.visibleFrame))
        f.discovery.windows = [first.0, second.0]
        let pair = try #require(f.manager.autoDetectAdjacentWindows(on: f.screen).first)
        let access = firstIsFullScreen ? first.1 : second.1
        access.isFullScreen = true
        #expect(!f.manager.isPairValidAndAdjacent(pair))
        #expect(f.manager.autoDetectAdjacentWindows(on: f.screen).isEmpty)
        #expect(f.manager.activePairs.isEmpty)

        f.manager.pair(first: first.0, second: second.0, orientation: .horizontal, on: f.screen)
        #expect(f.manager.activePairs.isEmpty)
        #expect(first.1.writes == 0 && second.1.writes == 0)
    }

    @Test func fullScreenPairStopsDividerFromInterceptingClicks() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let first = f.window(SnapZone.leftHalf.targetRect(for: f.screen.visibleFrame))
        let second = f.window(SnapZone.rightHalf.targetRect(for: f.screen.visibleFrame))
        f.discovery.windows = [first.0, second.0]
        #expect(f.manager.autoDetectAdjacentWindows(on: f.screen).count == 1)
        let state = f.manager.state(for: f.screen)
        let view = try #require(state.dividerWindow.contentView)
        first.1.isFullScreen = true

        #expect(view.hitTest(CGPoint(x: view.bounds.midX, y: view.bounds.midY)) == nil)
        #expect(state.pair == nil)
        #expect(!state.dividerWindow.isVisible)
    }

    @Test func exactAndAdaptiveIntentsUseTheSamePolicyForPreviewAndPlacement() throws {
        let savedPreference = UserDefaults.standard.object(forKey: "MacSnap.isDividerEnabled")
        defer {
            if let savedPreference {
                UserDefaults.standard.set(savedPreference, forKey: "MacSnap.isDividerEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "MacSnap.isDividerEnabled")
            }
        }
        // A user's disabled divider preference must not disable this enabled-flow fixture.
        UserDefaults.standard.set(false, forKey: "MacSnap.isDividerEnabled")
        let f = try Fixture()
        defer { f.cleanup() }
        let bounds = f.screen.visibleFrame
        let neighbor = f.window(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width * 0.65, height: bounds.height))
        let moving = f.window(bounds)
        f.discovery.windows = [neighbor.0]
        let exact = f.engine.previewRect(for: moving.0, to: .rightHalf, on: f.screen, forceExactSize: true)
        #expect(exact == SnapZone.rightHalf.targetRect(for: bounds))
        f.engine.snapWindow(moving.0, to: .rightHalf, on: f.screen, forceExactSize: true)
        try expectFramesClose(moving.0.cocoaFrame(primaryScreenHeight: f.height), exact)
        #expect(f.manager.state(for: f.screen).pair == nil)

        let adaptive = try #require(f.engine.previewRect(for: moving.0, to: .rightHalf, on: f.screen, forceExactSize: false))
        #expect(abs(adaptive.minX - (bounds.minX + bounds.width * 0.65)) < 0.001)
        f.engine.snapWindow(moving.0, to: .rightHalf, on: f.screen)
        try expectFramesClose(moving.0.cocoaFrame(primaryScreenHeight: f.height), adaptive)
        let pair = try #require(f.manager.state(for: f.screen).pair)
        #expect(pair.firstWindow.isSameWindow(as: neighbor.0))
        #expect(pair.secondWindow.isSameWindow(as: moving.0))
    }

    @Test func placementRefreshesObservationsAndFailedWritesDoNotRegister() throws {
        let f = try Fixture()
        defer { f.cleanup() }
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
        defer { f.cleanup() }
        let bounds = f.screen.visibleFrame
        let left = f.window(SnapZone.leftThird.targetRect(for: bounds))
        let center = f.window(bounds)
        let right = f.window(SnapZone.rightThird.targetRect(for: bounds))
        f.discovery.windows = [left.0, center.0, right.0]
        f.engine.snapWindow(center.0, to: .centerThird, on: f.screen, forceExactSize: true)
        try expectFramesClose(center.0.cocoaFrame(primaryScreenHeight: f.height), SnapZone.centerThird.targetRect(for: bounds))
        #expect(f.manager.autoDetectAdjacentWindows(on: f.screen).isEmpty)
        #expect(f.manager.activePairs.isEmpty)
        #expect(left.1.writes == 0 && right.1.writes == 0)
    }

    @Test func cancelledDropCannotPlaceOrRediscoverEvenIfSchedulerDeliversIt() throws {
        let f = try Fixture()
        defer { f.cleanup() }
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
        try expectFramesClose(moving.0.cocoaFrame(primaryScreenHeight: f.height), SnapZone.rightHalf.targetRect(for: f.screen.visibleFrame))
        f.clock.deliverAllIncludingCancelled()
        #expect(f.discovery.snapshotCount >= 1)
    }

    @Test func disconnectedDisplayCancelsDeferredPlacementAndDiscovery() throws {
        let f = try Fixture()
        defer { f.cleanup() }
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
        defer { f.cleanup() }
        let moving = f.window(f.screen.visibleFrame)
        f.engine.completeDrag(window: moving.0, zone: .leftHalf, screen: f.screen, forceExactSize: true)
        f.engine.snapWindow(moving.0, to: .rightHalf, on: f.screen, forceExactSize: true)
        f.clock.deliverAllIncludingCancelled()
        #expect(moving.1.writes == 1)
        try expectFramesClose(moving.0.cocoaFrame(primaryScreenHeight: f.height), SnapZone.rightHalf.targetRect(for: f.screen.visibleFrame))
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

    @Test func adaptivePlacementFitsLeftTopBottomAndBetweenTwoNeighbors() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let b = f.screen.visibleFrame
        let cases: [(SnapZone, [CGRect], CGRect)] = [
            (.leftHalf,
             [CGRect(x: b.minX + b.width * 0.35, y: b.minY, width: b.width * 0.65, height: b.height)],
             CGRect(x: b.minX, y: b.minY, width: b.width * 0.35, height: b.height)),
            (.topHalf,
             [CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height * 0.55)],
             CGRect(x: b.minX, y: b.minY + b.height * 0.55, width: b.width, height: b.height * 0.45)),
            (.bottomHalf,
             [CGRect(x: b.minX, y: b.minY + b.height * 0.35, width: b.width, height: b.height * 0.65)],
             CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height * 0.35)),
            (.centerThird,
             [CGRect(x: b.minX, y: b.minY, width: b.width * 0.35, height: b.height),
              CGRect(x: b.minX + b.width * 0.65, y: b.minY, width: b.width * 0.35, height: b.height)],
             CGRect(x: b.minX + b.width * 0.35, y: b.minY, width: b.width * 0.30, height: b.height))
        ]
        for (zone, neighbors, expected) in cases {
            f.manager.clearPairing()
            let moving = f.window(b)
            let stationary = neighbors.map { f.window($0) }
            f.discovery.windows = stationary.map(\.0)
            let preview = try #require(f.engine.previewRect(for: moving.0, to: zone, on: f.screen, forceExactSize: false))
            f.engine.snapWindow(moving.0, to: zone, on: f.screen)
            let placed = try #require(moving.0.cocoaFrame(primaryScreenHeight: f.height))
            for result in [preview, placed] {
                #expect(abs(result.minX - expected.minX) < 0.001)
                #expect(abs(result.minY - expected.minY) < 0.001)
                #expect(abs(result.width - expected.width) < 0.001)
                #expect(abs(result.height - expected.height) < 0.001)
            }
            #expect(stationary.allSatisfy { $0.1.writes == 0 })
        }
    }
}

/// Coordinate conversions involve subtraction of fractional points; compare geometry,
/// allowing only floating-point noise, far below any visible or native AX tolerance.
private func expectFramesClose(_ actual: CGRect?, _ expected: CGRect?,
                               sourceLocation: SourceLocation = #_sourceLocation) throws {
    let actual = try #require(actual, sourceLocation: sourceLocation)
    let expected = try #require(expected, sourceLocation: sourceLocation)
    #expect(abs(actual.minX - expected.minX) < 0.000001, sourceLocation: sourceLocation)
    #expect(abs(actual.minY - expected.minY) < 0.000001, sourceLocation: sourceLocation)
    #expect(abs(actual.width - expected.width) < 0.000001, sourceLocation: sourceLocation)
    #expect(abs(actual.height - expected.height) < 0.000001, sourceLocation: sourceLocation)
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
    private let previousDividerPreference: Any?

    init() throws {
        _ = NSApplication.shared
        screen = try #require(NSScreen.screens.first)
        height = screen.frame.height
        previousDividerPreference = UserDefaults.standard.object(forKey: "MacSnap.isDividerEnabled")
        UserDefaults.standard.set(true, forKey: "MacSnap.isDividerEnabled")
        screens = SnapScreens(screen: screen)
        discovery = SnapScene(primaryHeight: height)
        manager = PairedResizeManager(screenService: screens, windowDiscovery: discovery, isMasterEnabled: { true })
        engine = SnapEngine(screenService: screens, pairingManager: manager, discovery: discovery, scheduler: clock)
    }

    func cleanup() {
        manager.clearPairing()
        if let previousDividerPreference {
            UserDefaults.standard.set(previousDividerPreference, forKey: "MacSnap.isDividerEnabled")
        } else {
            UserDefaults.standard.removeObject(forKey: "MacSnap.isDividerEnabled")
        }
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
    private var fullScreen = false
    private var resizable = true
    private var limits = WindowSizeLimits(minimum: .zero, maximum: CGSize(width: 100000, height: 100000))
    var sizeLimits: WindowSizeLimits {
        get { lock.withLock { limits } }
        set { lock.withLock { limits = newValue } }
    }
    private var count = 0
    init(_ frame: CGRect) { stored = frame }
    var frame: CGRect? { lock.withLock { stored } }
    var isResizable: Bool {
        get { lock.withLock { resizable } }
        set { lock.withLock { resizable = newValue } }
    }
    var isFullScreen: Bool {
        get { lock.withLock { fullScreen } }
        set { lock.withLock { fullScreen = newValue } }
    }
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
