import AppKit
import ApplicationServices
import Testing
@testable import MacSnap

@MainActor
struct PairedResizeSessionTests {
    @Test(arguments: [false, true])
    func fullScreenMemberPreventsPairWrites(firstIsFullScreen: Bool) {
        let f = ResizeFixture()
        let access = firstIsFullScreen ? f.firstAccess : f.secondAccess
        access.isFullScreen = true
        #expect(!f.pair.applyCurrentSplit(primaryScreenHeight: 1000))
        #expect(f.writes.names.isEmpty)
        #expect(!f.session.begin())
        #expect(f.presentation.presentations == 0)
        #expect(f.session.phase == .invalidated)
    }

    @Test func enteringFullScreenDuringResizeInvalidatesWithoutWritingEitherWindow() {
        let f = ResizeFixture()
        #expect(f.session.begin())
        f.session.update(to: 1200)
        f.firstAccess.isFullScreen = true
        f.session.finish()
        #expect(f.session.phase == .invalidated)
        #expect(f.writes.names.isEmpty)
        #expect(f.reference.invalidations == 1)
    }

    @Test func enteringFullScreenBeforeSettlementPreventsPartnerCorrection() {
        let f = ResizeFixture(firstMinimum: CGSize(width: 900, height: 0))
        #expect(f.session.begin())
        f.session.update(to: 600)
        f.session.finish()
        #expect(f.session.phase == .settling)
        let writes = f.writes.names
        f.firstAccess.isFullScreen = true
        f.scheduler.runAll()
        #expect(f.session.phase == .invalidated)
        #expect(f.writes.names == writes)
    }

    @Test func draggingChangesOnlyPreviewThenReleaseCommitsAndSettles() {
        let f = ResizeFixture()
        #expect(f.session.begin())
        f.session.update(to: 1200)
        #expect(f.presentation.lastFrames?.0.width == 1200)
        #expect(f.presentation.lastFrames?.1.width == 600)
        #expect(f.writes.names.isEmpty)

        f.session.finish()
        #expect(f.writes.names == ["second", "first"])
        #expect(f.session.phase == .settling)
        #expect(f.scheduler.delays == [0.06])
        #expect(f.presentation.dismissals == [true])
        f.scheduler.runAll()
        #expect(f.session.phase == .finished)
        let expectedRatio: CGFloat = 2.0 / 3.0
        #expect(f.pair.ratio == expectedRatio)
        #expect(f.writes.names == ["second", "first"])
    }

    @Test func releaseShrinksBeforeExpandingInBothOrientations() {
        for orientation in [SplitOrientation.horizontal, .vertical] {
            for expandingFirst in [true, false] {
                let f = ResizeFixture(orientation: orientation)
                #expect(f.session.begin())
                let targetRatio: CGFloat = expandingFirst ? 2.0 / 3.0 : 1.0 / 3.0
                let coordinate = orientation == .horizontal ? 1800 * targetRatio : 1000 * (1 - targetRatio)
                f.session.update(to: coordinate)
                f.session.finish()
                #expect(f.writes.names == (expandingFirst ? ["second", "first"] : ["first", "second"]))
                f.scheduler.runAll()
                #expect(f.session.phase == .finished)
                #expect(f.reference.invalidations == 0)
            }
        }
    }

    @Test func minimumSizeReadbackRealignsPartnerToTheObservedFirstWindow() {
        let f = ResizeFixture(firstMinimum: CGSize(width: 900, height: 0))
        #expect(f.session.begin())
        f.session.update(to: 600)
        f.session.finish()
        #expect(f.first.cocoaFrame(primaryScreenHeight: 1000)?.width == 900)
        #expect(f.second.cocoaFrame(primaryScreenHeight: 1000)?.minX == 600)
        f.scheduler.runAll()
        #expect(f.session.phase == .finished)
        #expect(f.second.cocoaFrame(primaryScreenHeight: 1000) == CGRect(x: 900, y: 0, width: 900, height: 1000))
        #expect(f.pair.ratio == 0.5)
        #expect(f.writes.names == ["first", "second", "second"])
    }

    @Test func verticalMinimumSizeReadbackRealignsBottomWindow() {
        let f = ResizeFixture(orientation: .vertical, firstMinimum: CGSize(width: 0, height: 500))
        #expect(f.session.begin())
        f.session.update(to: 1000 * (2.0 / 3.0))
        f.session.finish()
        f.scheduler.runAll()
        #expect(f.session.phase == .finished)
        #expect(f.second.cocoaFrame(primaryScreenHeight: 1000) == CGRect(x: 0, y: 0, width: 1800, height: 500))
        #expect(f.pair.ratio == 0.5)
    }

    @Test func impossibleMinimumSizesInvalidateWithoutAnUnboundedRetry() {
        let f = ResizeFixture(
            firstMinimum: CGSize(width: 1000, height: 0),
            secondMinimum: CGSize(width: 1000, height: 0)
        )
        #expect(f.session.begin())
        f.session.update(to: 600)
        f.session.finish()
        f.scheduler.runAll()
        #expect(f.session.phase == .invalidated)
        #expect(f.reference.invalidations == 1)
        #expect(f.writes.names == ["first", "second", "second"])
        #expect(f.scheduler.pendingCount == 0)
    }

    @Test func unsupportedCrossAxisMinimumCannotClaimAFullDisplaySplit() {
        for orientation in [SplitOrientation.horizontal, .vertical] {
            for firstIsConstrained in [true, false] {
                for overflow in [CGFloat(10), CGFloat(200)] {
                    let minimum = orientation == .horizontal
                        ? CGSize(width: 0, height: 1000 + overflow)
                        : CGSize(width: 1800 + overflow, height: 0)
                    let f = ResizeFixture(
                        orientation: orientation,
                        firstMinimum: firstIsConstrained ? minimum : .zero,
                        secondMinimum: firstIsConstrained ? .zero : minimum
                    )
                    #expect(f.session.begin())
                    f.session.update(to: orientation == .horizontal ? 1200 : 1000 / 3.0)
                    f.session.finish()
                    f.scheduler.runAll()
                    #expect(f.session.phase == .invalidated)
                    #expect(f.reference.invalidations == 1)
                    #expect(f.scheduler.pendingCount == 0)
                }
            }
        }
    }

    @Test func failedShrinkingWriteDoesNotExpandTheOtherWindow() {
        let f = ResizeFixture()
        f.secondAccess.rejectWrites = true
        #expect(f.session.begin())
        f.session.update(to: 1200)
        f.session.finish()
        #expect(f.session.phase == .invalidated)
        #expect(f.writes.names == ["second"])
        #expect(f.first.cocoaFrame(primaryScreenHeight: 1000)?.width == 900)
        #expect(f.scheduler.pendingCount == 0)
    }

    @Test func failedExpansionInvalidatesWithoutSchedulingSettlement() {
        let f = ResizeFixture()
        f.firstAccess.rejectWrites = true
        #expect(f.session.begin())
        f.session.update(to: 1200)
        f.session.finish()
        #expect(f.session.phase == .invalidated)
        #expect(f.reference.invalidations == 1)
        #expect(f.writes.names == ["second", "first"])
        #expect(f.scheduler.pendingCount == 0)
    }

    @Test func closedWindowsAreHandledBeforeBeginDuringDragAndBeforeReadback() {
        let before = ResizeFixture()
        before.firstAccess.close()
        #expect(!before.session.begin())
        #expect(before.presentation.presentations == 0)
        #expect(before.writes.names.isEmpty)

        let during = ResizeFixture()
        #expect(during.session.begin())
        during.secondAccess.close()
        during.session.update(to: 1200)
        #expect(during.session.phase == .invalidated)
        #expect(during.writes.names.isEmpty)

        let after = ResizeFixture()
        #expect(after.session.begin())
        after.session.update(to: 1200)
        after.session.finish()
        after.firstAccess.close()
        after.scheduler.runAll()
        #expect(after.session.phase == .invalidated)
        #expect(after.writes.names == ["second", "first"])
    }

    @Test func cancellationRejectsEvenAClockThatDeliversCancelledWork() {
        let f = ResizeFixture()
        #expect(f.session.begin())
        f.session.update(to: 1200)
        f.session.finish()
        f.session.cancel()
        let updates = f.presentation.updates
        f.scheduler.runAll(deliverCancelled: true)
        #expect(f.session.phase == .cancelled)
        #expect(f.presentation.updates == updates)
        #expect(f.writes.names == ["second", "first"])
        #expect(f.reference.invalidations == 0)
    }

    @Test func aStaleReadbackCannotWriteOrDismissAnotherPair() {
        let f = ResizeFixture(firstMinimum: CGSize(width: 900, height: 0))
        #expect(f.session.begin())
        f.session.update(to: 600)
        f.session.finish()
        f.reference.current = false
        let dismissals = f.presentation.dismissals
        let updates = f.presentation.updates
        f.scheduler.runAll()
        #expect(f.session.phase == .cancelled)
        #expect(f.presentation.dismissals == dismissals)
        #expect(f.presentation.updates == updates)
        #expect(f.writes.names == ["first", "second"])
        #expect(f.reference.invalidations == 0)
    }

    @Test func replacingOrClearingScreenPairStateCancelsItsPendingLifetime() {
        _ = NSApplication.shared
        for replace in [true, false] {
            let f = ResizeFixture()
            let state = ScreenPairState(screenID: 1)
            state.pair = f.pair
            state.resizeSession = f.session
            #expect(f.session.begin())
            f.session.update(to: 1200)
            f.session.finish()
            if replace {
                state.pair = ResizeFixture().pair
            } else {
                state.clear()
            }
            f.scheduler.runAll(deliverCancelled: true)
            #expect(f.session.phase == .cancelled)
            #expect(state.resizeSession == nil)
            #expect(f.writes.names == ["second", "first"])
        }
    }

    @Test func removedDisplayPurgesPairAndCancelsDeferredWrites() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let screens = ResizeScreens(screen: screen)
        let manager = PairedResizeManager(
            screenService: screens, windowDiscovery: NoResizeWindows(), isMasterEnabled: { true }
        )
        defer { manager.clearPairing() }
        let f = ResizeFixture(firstMinimum: CGSize(width: screen.visibleFrame.width / 2, height: 0))
        f.pair.visibleFrame = screen.visibleFrame
        let state = manager.state(for: screen)
        state.pair = f.pair
        state.resizeSession = f.session
        #expect(f.session.begin())
        f.session.update(to: screen.visibleFrame.minX + screen.visibleFrame.width / 3)
        f.session.finish()
        let writesBeforeRemoval = f.writes.names

        screens.setScreens([])
        manager.handleScreenConfigurationChange()
        #expect(f.session.phase == .cancelled)
        #expect(state.pair == nil)
        #expect(state.resizeSession == nil)
        #expect(manager.activePairs.isEmpty)
        f.scheduler.runAll(deliverCancelled: true)
        #expect(f.writes.names == writesBeforeRemoval)

        // Even an old queued refresh must not recreate a pair on an absent display.
        #expect(manager.autoDetectAdjacentWindows(on: screen).isEmpty)
        screens.setScreens([screen])
        #expect(manager.state(for: screen) !== state)
    }

    @Test func screenGeometryMismatchCancelsSettlementBeforeRediscovery() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let screens = ResizeScreens(screen: screen)
        let manager = PairedResizeManager(
            screenService: screens, windowDiscovery: NoResizeWindows(), isMasterEnabled: { true }
        )
        defer { manager.clearPairing() }
        let f = ResizeFixture()
        f.pair.visibleFrame = screen.visibleFrame
        let state = manager.state(for: screen)
        state.pair = f.pair
        state.resizeSession = f.session
        #expect(f.session.begin())
        f.session.update(to: screen.visibleFrame.minX + screen.visibleFrame.width * 2 / 3)
        f.session.finish()
        let writesBeforeChange = f.writes.names

        // Represents a pair captured under a geometry that no longer matches its display.
        f.pair.visibleFrame = screen.visibleFrame.offsetBy(dx: 100, dy: 0)
        manager.autoDetectAdjacentWindows()
        #expect(f.session.phase == .cancelled)
        #expect(state.pair == nil)
        #expect(manager.activePairs.isEmpty)
        f.scheduler.runAll(deliverCancelled: true)
        #expect(f.writes.names == writesBeforeChange)
        #expect(manager.state(for: screen) !== state)
    }

    @Test func primaryReferenceHeightChangeCancelsEvenWhenDisplayGeometryIsUnchanged() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let visibleFrame = screen.visibleFrame
        let screens = ResizeScreens(screen: screen)
        let manager = PairedResizeManager(
            screenService: screens, windowDiscovery: NoResizeWindows(), isMasterEnabled: { true }
        )
        defer { manager.clearPairing() }
        let f = ResizeFixture(firstMinimum: CGSize(width: visibleFrame.width / 2, height: 0))
        f.pair.visibleFrame = visibleFrame
        let state = manager.state(for: screen)
        state.pair = f.pair
        state.resizeSession = f.session
        #expect(f.session.begin())
        f.session.update(to: visibleFrame.minX + visibleFrame.width / 3)
        f.session.finish()
        let writesBeforeChange = f.writes.names

        screens.setPrimaryScreenHeight(screens.primaryScreenHeight + 120)
        #expect(screen.visibleFrame == visibleFrame)
        manager.handleScreenConfigurationChange()
        #expect(f.session.phase == .cancelled)
        #expect(state.pair == nil)
        #expect(manager.activePairs.isEmpty)
        f.scheduler.runAll(deliverCancelled: true)
        #expect(f.writes.names == writesBeforeChange)
        #expect(manager.state(for: screen) !== state)
    }
}

@MainActor
private final class ResizeFixture {
    let pair: PairedSplit
    let first: WindowElement
    let second: WindowElement
    let firstAccess: ResizeFrameAccess
    let secondAccess: ResizeFrameAccess
    let writes = ResizeWriteLog()
    let presentation = ResizePresentation()
    let scheduler = ResizeScheduler()
    let reference = ResizeReference()
    let session: PairedResizeSession

    init(
        orientation: SplitOrientation = .horizontal,
        firstMinimum: CGSize = .zero,
        secondMinimum: CGSize = .zero
    ) {
        let firstFrame = orientation == .horizontal
            ? CGRect(x: 0, y: 0, width: 900, height: 1000)
            : CGRect(x: 0, y: 500, width: 1800, height: 500)
        let secondFrame = orientation == .horizontal
            ? CGRect(x: 900, y: 0, width: 900, height: 1000)
            : CGRect(x: 0, y: 0, width: 1800, height: 500)
        firstAccess = ResizeFrameAccess(name: "first", cocoaFrame: firstFrame, minimum: firstMinimum, writes: writes)
        secondAccess = ResizeFrameAccess(name: "second", cocoaFrame: secondFrame, minimum: secondMinimum, writes: writes)
        first = WindowElement(element: AXUIElementCreateSystemWide(), pid: 100, frameAccess: firstAccess, identity: UUID())
        second = WindowElement(element: AXUIElementCreateSystemWide(), pid: 100, frameAccess: secondAccess, identity: UUID())
        pair = PairedSplit(firstWindow: first, secondWindow: second, orientation: orientation,
                           visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1000))
        let reference = self.reference
        session = PairedResizeSession(
            pair: pair, primaryScreenHeight: 1000, presentation: presentation, scheduler: scheduler,
            isCurrent: { reference.current }, onInvalidated: { reference.invalidations += 1 }
        )
    }
}

@MainActor
private final class ResizeReference {
    var current = true
    var invalidations = 0
}

/// The production frame seam is Sendable; this scripted adapter protects every
/// mutable field with the same lock so test control does not introduce a race.
private final class ResizeFrameAccess: WindowFrameAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var storedFrame: CGRect?
    private var storedRejectWrites = false
    private var fullScreen = false
    private let name: String
    private let minimum: CGSize
    private let writes: ResizeWriteLog

    init(name: String, cocoaFrame: CGRect, minimum: CGSize, writes: ResizeWriteLog) {
        self.name = name
        self.minimum = minimum
        self.writes = writes
        self.storedFrame = ScreenGeometry.cocoaToAX(cocoaRect: cocoaFrame, primaryScreenHeight: 1000)
    }

    var frame: CGRect? { lock.withLock { storedFrame } }
    var isResizable: Bool { true }
    var isFullScreen: Bool {
        get { lock.withLock { fullScreen } }
        set { lock.withLock { fullScreen = newValue } }
    }
    var rejectWrites: Bool {
        get { lock.withLock { storedRejectWrites } }
        set { lock.withLock { storedRejectWrites = newValue } }
    }

    func close() { lock.withLock { storedFrame = nil } }

    func setFrame(_ frame: CGRect) -> Bool {
        writes.record(name)
        return lock.withLock {
            guard storedFrame != nil && !storedRejectWrites else { return false }
            storedFrame = CGRect(
                origin: frame.origin,
                size: CGSize(width: max(frame.width, minimum.width), height: max(frame.height, minimum.height))
            )
            return true
        }
    }
}

private final class ResizeWriteLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNames: [String] = []
    var names: [String] { lock.withLock { storedNames } }
    func record(_ name: String) { lock.withLock { storedNames.append(name) } }
}

@MainActor
private final class ResizePresentation: PairedResizePresenting {
    var presentations = 0
    var updates = 0
    var dismissals: [Bool] = []
    var lastFrames: (CGRect, CGRect)?
    func present(pair: PairedSplit) { presentations += 1; lastFrames = pair.calculateFrames() }
    func update(pair: PairedSplit) { updates += 1; lastFrames = pair.calculateFrames() }
    func dismiss(animated: Bool) { dismissals.append(animated) }
}

@MainActor
private final class ResizeScheduler: ActionScheduling {
    private struct Entry {
        let token: ResizeScheduledAction
        let action: @MainActor () -> Void
    }
    private var entries: [Entry] = []
    var delays: [TimeInterval] = []
    var pendingCount: Int { entries.count }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledAction {
        let token = ResizeScheduledAction()
        delays.append(delay)
        entries.append(Entry(token: token, action: action))
        return token
    }

    func runAll(deliverCancelled: Bool = false) {
        let pending = entries
        entries = []
        for entry in pending where deliverCancelled || !entry.token.isCancelled { entry.action() }
    }
}

@MainActor
private final class ResizeScheduledAction: ScheduledAction {
    var isCancelled = false
    func cancel() { isCancelled = true }
}

private final class ResizeScreens: ScreenServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var connected: [NSScreen]
    private var referenceHeight: CGFloat

    init(screen: NSScreen) {
        connected = [screen]
        referenceHeight = ScreenService.shared.primaryScreenHeight
    }

    var screens: [NSScreen] { lock.withLock { connected } }
    var primaryScreen: NSScreen? { screens.first }
    var primaryScreenHeight: CGFloat { lock.withLock { referenceHeight } }
    func setScreens(_ screens: [NSScreen]) { lock.withLock { connected = screens } }
    func setPrimaryScreenHeight(_ height: CGFloat) { lock.withLock { referenceHeight = height } }
    func screenContaining(point: CGPoint) -> NSScreen? { screens.first { $0.frame.contains(point) } }
    func screenContaining(rect: CGRect) -> NSScreen? { screens.first { $0.frame.intersects(rect) } }
}

@MainActor
private final class NoResizeWindows: WindowDiscovering {
    func snapshot(primaryScreenHeight: CGFloat) -> WindowSnapshot? {
        // Topology cleanup must precede even an unavailable native observation.
        nil
    }
    func window(atCocoaPoint point: CGPoint, excluding: WindowElement?, primaryScreenHeight: CGFloat) -> WindowElement? {
        nil
    }
}
