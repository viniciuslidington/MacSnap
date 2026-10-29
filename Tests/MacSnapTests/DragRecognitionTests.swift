import CoreGraphics
import AppKit
import ApplicationServices
import Testing
@testable import MacSnap

struct DragRecognitionTests {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let windowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let start = CGPoint(x: 500, y: 650)

    @Test func acceptsAtExactlyFourteenPointsFromTheOriginalMovement() {
        var recognition = DragRecognition<Int>()
        var resolutions = 0
        func candidate() -> DragRecognition<Int>.Candidate {
            resolutions += 1
            return .init(window: 7, frame: windowFrame)
        }

        let dragBegan1 = recognition.drag(at: start, visibleFrame: visibleFrame, candidate: candidate)
        #expect(!dragBegan1)
        #expect(!recognition.isDragging)
        #expect(recognition.window == 7)
        let dragBegan2 = recognition.drag(at: CGPoint(x: 506, y: 658), visibleFrame: visibleFrame, candidate: candidate)
        #expect(!dragBegan2)
        let dragBegan3 = recognition.drag(at: CGPoint(x: 514, y: 650), visibleFrame: visibleFrame, candidate: candidate)
        #expect(dragBegan3)
        #expect(recognition.isDragging)
        let dragBegan4 = recognition.drag(at: CGPoint(x: 540, y: 650), visibleFrame: visibleFrame, candidate: candidate)
        #expect(!dragBegan4)
        #expect(resolutions == 1)

        let release = recognition.release()
        #expect(release.window == 7)
        #expect(release.wasDragging)
        #expect(recognition.window == nil)
        #expect(!recognition.isDragging)
    }

    @Test func rejectedContentDoesNotBecomeADragWhenItPassesThroughTheHeader() {
        var recognition = DragRecognition<Int>()
        var resolutions = 0
        func candidate() -> DragRecognition<Int>.Candidate {
            resolutions += 1
            return .init(window: 3, frame: windowFrame)
        }

        let dragBegan5 = recognition.drag(at: CGPoint(x: 500, y: 500), visibleFrame: visibleFrame, candidate: candidate)
        #expect(!dragBegan5)
        #expect(recognition.isIgnored)
        let dragBegan6 = recognition.drag(at: start, visibleFrame: visibleFrame, candidate: candidate)
        #expect(!dragBegan6)
        let dragBegan7 = recognition.drag(at: CGPoint(x: 514, y: 650), visibleFrame: visibleFrame, candidate: candidate)
        #expect(!dragBegan7)
        #expect(resolutions == 1)
        let release = recognition.release()
        #expect(release.window == nil)
        #expect(!release.wasDragging)

        let dragBegan8 = recognition.drag(at: start, visibleFrame: visibleFrame, candidate: candidate)
        #expect(!dragBegan8)
        let dragBegan9 = recognition.drag(at: CGPoint(x: 514, y: 650), visibleFrame: visibleFrame, candidate: candidate)
        #expect(dragBegan9)
        #expect(resolutions == 2)
    }

    @Test func rejectedDesktopAndOwnWindowsStayIgnoredUntilRelease() {
        for candidate in [
            DragRecognition<Int>.Candidate(window: 1, frame: windowFrame, isDesktop: true),
            DragRecognition<Int>.Candidate(window: 2, frame: windowFrame, isOwnWindow: true)
        ] {
            var recognition = DragRecognition<Int>()
            let dragBegan10 = recognition.drag(at: start, visibleFrame: visibleFrame) { candidate }
            #expect(!dragBegan10)
            #expect(recognition.isIgnored)
            let dragBegan11 = recognition.drag(at: CGPoint(x: 520, y: 650), visibleFrame: visibleFrame) {
                .init(window: 9, frame: windowFrame)
            }
            #expect(!dragBegan11)
            #expect(recognition.window == nil)
            let releasedGesture12 = recognition.release()
            #expect(!releasedGesture12.wasDragging)
        }
    }

    @Test func missingWindowDoesNotGetResolvedAgainDuringTheSameGesture() {
        var recognition = DragRecognition<Int>()
        var resolutions = 0
        let dragBegan13 = recognition.drag(at: start, visibleFrame: visibleFrame) {
            resolutions += 1
            return nil
        }
        #expect(!dragBegan13)
        let dragBegan14 = recognition.drag(at: CGPoint(x: 520, y: 650), visibleFrame: visibleFrame) {
            resolutions += 1
            return .init(window: 2, frame: windowFrame)
        }
        #expect(!dragBegan14)
        #expect(resolutions == 1)
        #expect(recognition.isIgnored)
        let releasedGesture15 = recognition.release()
        #expect(!releasedGesture15.wasDragging)
    }

    @Test func excludedUsableAreaNeverQueriesNativeWindowFacts() {
        let usable = CGRect(x: 0, y: 70, width: 1920, height: 985)
        for point in [CGPoint(x: 200, y: 1065), CGPoint(x: 200, y: 1054.5), CGPoint(x: 960, y: 35)] {
            var recognition = DragRecognition<Int>()
            var resolutions = 0
            let dragBegan16 = recognition.drag(at: point, visibleFrame: usable) {
                resolutions += 1
                return .init(window: 1, frame: windowFrame)
            }
            #expect(!dragBegan16)
            #expect(recognition.isIgnored)
            #expect(resolutions == 0)
        }
        var recognition = DragRecognition<Int>()
        let dragBegan17 = recognition.drag(at: start, visibleFrame: nil) {
            Issue.record("A gesture without a display must not query a window")
            return .init(window: 1, frame: windowFrame)
        }
        #expect(!dragBegan17)
        #expect(recognition.isIgnored)
    }

    @Test func subThresholdReleaseCannotCommitAndNextGestureStartsFresh() {
        var recognition = DragRecognition<Int>()
        recognition.drag(at: start, visibleFrame: visibleFrame) { .init(window: 1, frame: windowFrame) }
        recognition.drag(at: CGPoint(x: 510, y: 650), visibleFrame: visibleFrame) {
            Issue.record("A candidate must not be resolved again")
            return nil
        }
        let release = recognition.release()
        #expect(release.window == 1)
        #expect(!release.wasDragging)
        #expect(!recognition.isIgnored)
        recognition.drag(at: start, visibleFrame: visibleFrame) { .init(window: 2, frame: windowFrame) }
        let dragBegan18 = recognition.drag(at: CGPoint(x: 514, y: 650), visibleFrame: visibleFrame) { nil }
        #expect(dragBegan18)
        let releasedGesture19 = recognition.release()
        #expect(releasedGesture19.window == 2)
    }

    @Test func crossingDisplaysKeepsTheCapturedWindowAndDoesNotReadmit() {
        var recognition = DragRecognition<Int>()
        recognition.drag(at: start, visibleFrame: visibleFrame) { .init(window: 1, frame: windowFrame) }
        let otherScreen = CGRect(x: 1920, y: -200, width: 1080, height: 1920)
        let dragBegan20 = recognition.drag(at: CGPoint(x: 1950, y: 650), visibleFrame: otherScreen) {
            Issue.record("Crossing displays must preserve the captured window")
            return .init(window: 2, frame: .zero)
        }
        #expect(dragBegan20)
        #expect(recognition.window == 1)
        let releasedGesture21 = recognition.release()
        #expect(releasedGesture21.wasDragging)
    }

    @Test func suppressionDiscardsCaptureAndIgnoresTheHeldGestureUntilRelease() {
        var recognition = DragRecognition<Int>()
        recognition.drag(at: start, visibleFrame: visibleFrame) { .init(window: 1, frame: windowFrame) }
        recognition.drag(at: CGPoint(x: 514, y: 650), visibleFrame: visibleFrame) { nil }
        recognition.reset(ignoringUntilRelease: true)
        #expect(recognition.isIgnored)
        #expect(recognition.window == nil)
        #expect(!recognition.isDragging)
        let dragBegan22 = recognition.drag(at: start, visibleFrame: visibleFrame) {
            Issue.record("A suppressed held gesture must not resume")
            return .init(window: 2, frame: windowFrame)
        }
        #expect(!dragBegan22)
        let releasedGesture23 = recognition.release()
        #expect(!releasedGesture23.wasDragging)
        recognition.drag(at: start, visibleFrame: visibleFrame) { .init(window: 2, frame: windowFrame) }
        let dragBegan24 = recognition.drag(at: CGPoint(x: 514, y: 650), visibleFrame: visibleFrame) { nil }
        #expect(dragBegan24)
        #expect(recognition.window == 2)
    }

    @Test func stoppingAndRestartingHasNoOldCaptureOrRejection() {
        var recognition = DragRecognition<Int>()
        recognition.drag(at: start, visibleFrame: visibleFrame) { .init(window: 1, frame: windowFrame) }
        recognition.reset()
        #expect(recognition.window == nil)
        #expect(!recognition.isDragging)
        #expect(!recognition.isIgnored)
        recognition.drag(at: start, visibleFrame: visibleFrame) { .init(window: 2, frame: windowFrame) }
        #expect(!recognition.isDragging)
        let dragBegan25 = recognition.drag(at: CGPoint(x: 514, y: 650), visibleFrame: visibleFrame) { nil }
        #expect(dragBegan25)
        let releasedGesture26 = recognition.release()
        #expect(releasedGesture26.window == 2)
    }
}

@MainActor
@Suite(.serialized)
struct GlobalEventMonitorIntegrationTests {
    @Test func acceptedGestureUsesOneCandidateAndTheSnappingInterfaceForPreviewAndRelease() throws {
        let fixture = try MonitorFixture()
        defer { fixture.cleanUp() }
        let monitor = fixture.monitor

        monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start.offsetBy(dx: 10))
        #expect(fixture.engine.previews.isEmpty)
        monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start.offsetBy(dx: 14))
        monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)

        #expect(fixture.access.hitTests == 1)
        #expect(fixture.engine.previews.last == fixture.edgeZone)
        #expect(fixture.engine.drops.count == 1)
        #expect(fixture.engine.drops.first?.window === fixture.window)
        #expect(fixture.engine.drops.first?.zone == fixture.edgeZone)
        #expect(fixture.engine.drops.first?.exact == false)
        #expect(fixture.engine.cancellations > 0)
    }

    @Test func rejectedGestureCannotSnapAndReleaseAdmitsTheNextGesture() throws {
        let fixture = try MonitorFixture()
        defer { fixture.cleanUp() }
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.body)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.previews.isEmpty)
        #expect(fixture.engine.drops.isEmpty)
        #expect(fixture.access.hitTests == 1)

        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start.offsetBy(dx: 14))
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.start.offsetBy(dx: 14))
        #expect(fixture.engine.drops.count == 1)
        #expect(fixture.engine.drops.first?.zone == nil)
        #expect(fixture.access.hitTests == 2)
    }

    @Test func pauseResumeDiscardsTheOldGestureUntilMouseUp() throws {
        let fixture = try MonitorFixture()
        defer { fixture.cleanUp() }
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start.offsetBy(dx: 14))
        let observationsBeforePause = fixture.discovery.snapshots
        fixture.monitor.isMasterEnabled = false
        fixture.monitor.isMasterEnabled = true
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.drops.isEmpty)
        #expect(fixture.engine.previews.isEmpty)

        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start.offsetBy(dx: 14))
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.drops.count == 1)
        #expect(fixture.access.hitTests == 2)
        #expect(fixture.discovery.snapshots == observationsBeforePause + 1)
    }

    @Test func dividerSuppressionAndStopDiscardTheCapturedWindow() throws {
        let fixture = try MonitorFixture()
        defer { fixture.cleanUp() }
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start.offsetBy(dx: 14))

        let state = fixture.pairing.state(for: fixture.screen)
        let dividerView = try #require(state.dividerWindow.contentView)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        dividerView.mouseDown(with: event)
        #expect(fixture.pairing.isDraggingDivider)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        state.dividerWindow.orderOut(nil)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.drops.isEmpty)

        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.stopMonitoring()
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start.offsetBy(dx: 14))
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.drops.isEmpty)
        #expect(fixture.access.hitTests == 3)
    }

    @Test func missingDisplayDuringMovementDiscardsThePreviouslySelectedTarget() throws {
        let fixture = try MonitorFixture()
        defer { fixture.cleanUp() }
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.previews.last == fixture.edgeZone)
        let cancellations = fixture.engine.cancellations

        fixture.screens.isConnected = false
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.drops.isEmpty)
        #expect(fixture.engine.cancellations > cancellations)
    }

    @Test func removedDisplayAtReleaseCannotUseTheRetainedPreviewScreen() throws {
        let fixture = try MonitorFixture()
        defer { fixture.cleanUp() }
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.previews.last == fixture.edgeZone)

        fixture.screens.isConnected = false
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.drops.isEmpty)
    }

    @Test func tapRecoveryWhileIdleStartsFreshButCancelsAnActiveHeldGesture() throws {
        let fixture = try MonitorFixture()
        defer { fixture.cleanUp() }
        fixture.monitor.handleEvent(type: .tapDisabledByTimeout, atCocoaPoint: .zero)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.drops.count == 1)

        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start.offsetBy(dx: 14))
        fixture.monitor.handleEvent(type: .tapDisabledByUserInput, atCocoaPoint: .zero)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.drops.count == 1)

        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.start)
        fixture.monitor.handleEvent(type: .leftMouseDragged, atCocoaPoint: fixture.edge)
        fixture.monitor.handleEvent(type: .leftMouseUp, atCocoaPoint: fixture.edge)
        #expect(fixture.engine.drops.count == 2)
    }
}

@MainActor
private final class MonitorFixture {
    let screen: NSScreen
    let window: WindowElement
    let access: MonitorTestAccessibility
    let engine: MonitorTestSnapEngine
    let discovery: MonitorTestDiscovery
    let screens: MonitorTestScreens
    let pairing: PairedResizeManager
    let monitor: GlobalEventMonitor
    let start: CGPoint
    let body: CGPoint
    let edge: CGPoint
    let edgeZone: SnapZone
    private let preferences: [String: Any]
    private static let keys = ["MacSnap.isMasterEnabled", "MacSnap.isTopSnapBarEnabled", "MacSnap.isEdgeSnapEnabled", "MacSnap.isDividerEnabled"]

    init() throws {
        _ = NSApplication.shared
        screen = try #require(NSScreen.screens.first, "Native event-shell integration needs a display; DragRecognitionTests remain display-independent")
        preferences = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in
            UserDefaults.standard.object(forKey: key).map { (key, $0) }
        })
        let visible = screen.visibleFrame
        let frame = CGRect(
            x: visible.minX + visible.width * 0.15, y: visible.minY + visible.height * 0.15,
            width: visible.width * 0.5, height: visible.height * 0.5
        )
        start = CGPoint(x: frame.midX, y: frame.maxY - 20)
        body = CGPoint(x: frame.midX, y: frame.midY)
        edge = CGPoint(x: visible.minX + 1, y: visible.midY)
        edgeZone = screen.isPortrait ? .middleThird : .leftHalf
        let frames = MonitorTestFrameAccess(frame: ScreenGeometry.cocoaToAX(cocoaRect: frame, primaryScreenHeight: screen.frame.height))
        window = WindowElement(element: AXUIElementCreateSystemWide(), pid: ProcessInfo.processInfo.processIdentifier + 1, frameAccess: frames, identity: UUID())
        access = MonitorTestAccessibility(window: window)
        engine = MonitorTestSnapEngine()
        discovery = MonitorTestDiscovery()
        screens = MonitorTestScreens(screen: screen)
        pairing = PairedResizeManager(screenService: screens, accessibilityService: access, windowDiscovery: discovery, isMasterEnabled: { true })
        pairing.isDividerEnabled = true
        monitor = GlobalEventMonitor(screenService: screens, accessibilityService: access, snapEngine: engine, pairingManager: pairing)
        monitor.isMasterEnabled = true
        monitor.isTopSnapBarEnabled = false
        monitor.isEdgeSnapEnabled = true
        engine.cancellations = 0
    }

    func cleanUp() {
        monitor.stopMonitoring()
        pairing.clearPairing()
        for key in Self.keys {
            if let value = preferences[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y) }
}

private struct MonitorTestFrameAccess: WindowFrameAccess {
    let frame: CGRect?
    var isResizable: Bool { true }
    func setFrame(_ frame: CGRect) -> Bool { false }
}

/// Every mutable field of this scripted screen adapter is protected by the lock.
private final class MonitorTestScreens: ScreenServiceProtocol, @unchecked Sendable {
    let screen: NSScreen
    private let lock = NSLock()
    private var connected = true
    init(screen: NSScreen) { self.screen = screen }
    var isConnected: Bool {
        get { lock.withLock { connected } }
        set { lock.withLock { connected = newValue } }
    }
    var screens: [NSScreen] { isConnected ? [screen] : [] }
    var primaryScreen: NSScreen? { isConnected ? screen : nil }
    var primaryScreenHeight: CGFloat { isConnected ? screen.frame.height : 0 }
    func screenContaining(point: CGPoint) -> NSScreen? { isConnected ? screen : nil }
    func screenContaining(rect: CGRect) -> NSScreen? { isConnected ? screen : nil }
}

private final class MonitorTestAccessibility: AccessibilityServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var hitTestCount = 0
    private let window: WindowElement
    init(window: WindowElement) { self.window = window }
    var hitTests: Int { lock.withLock { hitTestCount } }
    func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool { true }
    func getFocusedWindow() -> WindowElement? { window }
    func getWindowUnderPoint(_ point: CGPoint) -> WindowElement? {
        lock.withLock { hitTestCount += 1 }
        return window
    }
}

@MainActor
private final class MonitorTestDiscovery: WindowDiscovering {
    private(set) var snapshots = 0
    func snapshot(primaryScreenHeight: CGFloat) -> WindowSnapshot? {
        snapshots += 1
        return WindowSnapshot(windows: []) { _ in nil }
    }
    func window(atCocoaPoint point: CGPoint, excluding: WindowElement?, primaryScreenHeight: CGFloat) -> WindowElement? { nil }
}

@MainActor
private final class MonitorTestSnapEngine: WindowSnappingProtocol {
    struct Drop {
        let window: WindowElement?
        let zone: SnapZone?
        let exact: Bool
    }
    var previews: [SnapZone] = []
    var drops: [Drop] = []
    var cancellations = 0
    func snapFocusedWindow(to zone: SnapZone) {}
    func snapWindow(_ window: WindowElement, to zone: SnapZone, on screen: NSScreen, forceExactSize: Bool) {}
    func previewRect(for window: WindowElement, to zone: SnapZone, on screen: NSScreen, forceExactSize: Bool) -> CGRect {
        previews.append(zone)
        return zone.targetRect(for: screen.visibleFrame)
    }
    func completeDrag(window: WindowElement?, zone: SnapZone?, screen: NSScreen?, forceExactSize: Bool) {
        drops.append(Drop(window: window, zone: zone, exact: forceExactSize))
    }
    func cancelPendingOperations() { cancellations += 1 }
}
