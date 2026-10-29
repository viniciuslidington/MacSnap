import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import MacSnap

@MainActor
struct WindowDiscoveryTests {
    @Test func managerDetectsExactSameAppPairOcclusionAndObservationAvailability() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let height = ScreenService.shared.primaryScreenHeight
        let bounds = screen.visibleFrame
        let firstFrame = SnapZone.leftHalf.targetRect(for: bounds)
        let secondFrame = SnapZone.rightHalf.targetRect(for: bounds)
        let coveringFrame = CGRect(x: bounds.midX - 100, y: bounds.midY - 100, width: 200, height: 200)
        let firstAccess = DiscoveryFrameAccess(frame: ScreenGeometry.cocoaToAX(cocoaRect: firstFrame, primaryScreenHeight: height))
        let secondAccess = DiscoveryFrameAccess(frame: ScreenGeometry.cocoaToAX(cocoaRect: secondFrame, primaryScreenHeight: height))
        let coveringAccess = DiscoveryFrameAccess(frame: ScreenGeometry.cocoaToAX(cocoaRect: coveringFrame, primaryScreenHeight: height))
        let first = window(pid: 5000, backend: firstAccess)
        let second = window(pid: 5000, backend: secondAccess)
        let covering = window(pid: 5000, backend: coveringAccess)
        let firstInfo = info(id: 1, pid: 5000, cocoaFrame: firstFrame, primaryScreenHeight: height)
        let secondInfo = info(id: 2, pid: 5000, cocoaFrame: secondFrame, primaryScreenHeight: height)
        let coveringInfo = info(id: 3, pid: 5000, cocoaFrame: coveringFrame, primaryScreenHeight: height)
        var observations: [[String: Any]]? = [firstInfo, secondInfo]
        let discovery = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: nil), currentProcessID: 99,
            windowInfo: { observations }, applicationWindows: { _ in [first, second, covering] }
        )
        let manager = PairedResizeManager(windowDiscovery: discovery, isMasterEnabled: { true })
        let preferenceKey = "MacSnap.isDividerEnabled"
        let previousPreference = UserDefaults.standard.object(forKey: preferenceKey)
        defer {
            manager.clearPairing()
            if let previousPreference { UserDefaults.standard.set(previousPreference, forKey: preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: preferenceKey) }
        }
        manager.isDividerEnabled = true

        let pairs = manager.autoDetectAdjacentWindows(on: screen)
        #expect(pairs.count == 1)
        let pair = try #require(pairs.first)
        #expect(pair.firstWindow.isSameWindow(as: first))
        #expect(pair.secondWindow.isSameWindow(as: second))
        #expect(pair.firstWindow.pid == pair.secondWindow.pid)
        #expect(pair.orientation == .horizontal)
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        #expect(!manager.isPairOccluded(atCocoaPoint: point, for: pair))

        observations = [coveringInfo, firstInfo, secondInfo]
        #expect(manager.isPairOccluded(atCocoaPoint: point, for: pair))
        #expect(manager.state(for: screen).pair === pair)

        observations = nil
        #expect(manager.autoDetectAdjacentWindows(on: screen).isEmpty)
        #expect(manager.state(for: screen).pair === pair)
        #expect(manager.isPairOccluded(atCocoaPoint: point, for: pair))

        observations = []
        #expect(manager.autoDetectAdjacentWindows(on: screen).isEmpty)
        #expect(manager.state(for: screen).pair == nil)
        #expect(manager.activePairs.isEmpty)
        #expect(firstAccess.writes == 0 && secondAccess.writes == 0 && coveringAccess.writes == 0)
    }

    @Test func frameAdapterSupportsReadbackRejectionAndDistinctSameProcessWindows() {
        let backend = DiscoveryFrameAccess(frame: CGRect(x: 100, y: 0, width: 500, height: 800))
        let first = window(pid: 5000, backend: backend)
        let second = window(pid: 5000, backend: backend)
        #expect(!first.isSameWindow(as: second))
        #expect(first.isSameWindow(as: first))
        #expect(first.cocoaFrame(primaryScreenHeight: 1000) == CGRect(x: 100, y: 200, width: 500, height: 800))
        let target = CGRect(x: 600, y: 100, width: 700, height: 900)
        #expect(first.setCocoaFrame(target, primaryScreenHeight: 1000))
        #expect(first.cocoaFrame(primaryScreenHeight: 1000) == target)
        #expect(!first.setAXFrame(.zero))
        #expect(!first.setAXFrame(CGRect(x: CGFloat.nan, y: 0, width: 500, height: 800)))
        let rejecting = DiscoveryFrameAccess(frame: backend.frame, acceptsWrites: false)
        #expect(!window(pid: 5001, backend: rejecting).setCocoaFrame(target, primaryScreenHeight: 1000))
    }

    @Test func malformedNativeAXValuesAreRejectedBeforeUnpacking() {
        #expect(AXWindowFrameAccess.point(from: "not an AXValue" as CFString) == nil)
        #expect(AXWindowFrameAccess.size(from: kCFBooleanTrue) == nil)
        #expect(AXWindowFrameAccess.point(from: nil) == nil)
        var point = CGPoint(x: 42, y: 13)
        let pointValue = AXValueCreate(.cgPoint, &point)!
        #expect(AXWindowFrameAccess.point(from: pointValue) == point)
        #expect(AXWindowFrameAccess.size(from: pointValue) == nil)
        var size = CGSize(width: 500, height: 300)
        let sizeValue = AXValueCreate(.cgSize, &size)!
        #expect(AXWindowFrameAccess.size(from: sizeValue) == size)
        #expect(AXWindowFrameAccess.point(from: sizeValue) == nil)
        let invalidNativeWindow = AXWindowFrameAccess(element: AXUIElementCreateSystemWide())
        #expect(invalidNativeWindow.frame == nil)
        #expect(!invalidNativeWindow.setFrame(CGRect(x: 0, y: 0, width: 500, height: 300)))
    }

    @Test func snapshotResolvesSameAppWindowsOncePerPIDAndPreservesCoordinates() throws {
        let leftFrame = CGRect(x: -1000, y: -800, width: 500, height: 800)
        let rightFrame = CGRect(x: -500, y: -800, width: 500, height: 800)
        let first = window(pid: 5000, cocoaFrame: leftFrame)
        let second = window(pid: 5000, cocoaFrame: rightFrame)
        var listReads = 0
        let discovery = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: nil), currentProcessID: 99,
            windowInfo: { [info(id: 1, pid: 5000, cocoaFrame: leftFrame), info(id: 2, pid: 5000, cocoaFrame: rightFrame)] },
            applicationWindows: { pid in
                #expect(pid == 5000)
                listReads += 1
                return [first, second]
            }
        )
        let snapshot = try #require(discovery.snapshot(primaryScreenHeight: 1000))
        #expect(snapshot.windows.map(\.frame) == [leftFrame, rightFrame])
        #expect(listReads == 0)
        #expect(snapshot.element(for: snapshot.windows[0])?.isSameWindow(as: first) == true)
        #expect(snapshot.element(for: snapshot.windows[1])?.isSameWindow(as: second) == true)
        #expect(snapshot.element(for: snapshot.windows[0])?.isSameWindow(as: first) == true)
        #expect(listReads == 1)
    }

    @Test func thirdWindowOfSameApplicationOccludesTheDivider() throws {
        let aFrame = CGRect(x: 0, y: 0, width: 500, height: 1000)
        let bFrame = CGRect(x: 500, y: 0, width: 500, height: 1000)
        let cFrame = CGRect(x: 400, y: 300, width: 400, height: 400)
        let first = window(pid: 5000, cocoaFrame: aFrame)
        let second = window(pid: 5000, cocoaFrame: bFrame)
        let covering = window(pid: 5000, cocoaFrame: cFrame)
        let discovery = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: nil), currentProcessID: 99,
            windowInfo: { [info(id: 3, pid: 5000, cocoaFrame: cFrame), info(id: 1, pid: 5000, cocoaFrame: aFrame), info(id: 2, pid: 5000, cocoaFrame: bFrame)] },
            applicationWindows: { _ in [first, second, covering] }
        )
        let snapshot = try #require(discovery.snapshot(primaryScreenHeight: 1000))
        #expect(snapshot.isOccluded(at: CGPoint(x: 500, y: 500), pairedFirst: first, pairedSecond: second))
        #expect(!snapshot.isOccluded(at: CGPoint(x: 500, y: 100), pairedFirst: first, pairedSecond: second))
        #expect(!snapshot.isOccluded(at: CGPoint(x: -100, y: -100), pairedFirst: first, pairedSecond: second))
    }

    @Test func ambiguousOrUnavailableWindowIdentityDoesNotPermitDividerInteraction() throws {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 1000)
        let first = window(pid: 5000, cocoaFrame: frame)
        let duplicateGeometry = window(pid: 5000, cocoaFrame: frame)
        let discovery = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: nil), currentProcessID: 99,
            windowInfo: { [info(id: 1, pid: 5000, cocoaFrame: frame)] },
            applicationWindows: { _ in [first, duplicateGeometry] }
        )
        let snapshot = try #require(discovery.snapshot(primaryScreenHeight: 1000))
        #expect(snapshot.element(for: snapshot.windows[0]) == nil)
        #expect(snapshot.isOccluded(at: CGPoint(x: 250, y: 500), pairedFirst: first, pairedSecond: duplicateGeometry))
        let unresolvable = WindowSnapshot(windows: snapshot.windows) { _ in nil }
        #expect(unresolvable.isOccluded(at: CGPoint(x: 250, y: 500), pairedFirst: first, pairedSecond: duplicateGeometry))
    }

    @Test func oneElementCannotResolveToTwoObservedWindows() {
        let firstObservation = WindowObservation(windowID: 1, pid: 5000, frame: CGRect(x: 0, y: 0, width: 500, height: 1000))
        let secondObservation = WindowObservation(windowID: 2, pid: 5000, frame: CGRect(x: 500, y: 0, width: 500, height: 1000))
        let first = window(pid: 5000, cocoaFrame: firstObservation.frame)
        let snapshot = WindowSnapshot(windows: [firstObservation, secondObservation]) { _ in first }
        #expect(snapshot.element(for: firstObservation) != nil)
        #expect(snapshot.element(for: secondObservation) == nil)
    }

    @Test func pointLookupFallsBackToDistinctWindowOfSameApplication() {
        let first = window(pid: 5000, cocoaFrame: CGRect(x: 0, y: 0, width: 500, height: 1000))
        let second = window(pid: 5000, cocoaFrame: CGRect(x: 500, y: 0, width: 500, height: 1000))
        let discovery = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: first), currentProcessID: 99,
            windowInfo: { [info(id: 1, pid: 5000, cocoaFrame: CGRect(x: 0, y: 0, width: 500, height: 1000)), info(id: 2, pid: 5000, cocoaFrame: CGRect(x: 500, y: 0, width: 500, height: 1000))] },
            applicationWindows: { _ in [first, second] }
        )
        let found = discovery.window(atCocoaPoint: CGPoint(x: 750, y: 500), excluding: first, primaryScreenHeight: 1000)
        #expect(found?.isSameWindow(as: second) == true)
        #expect(discovery.window(atCocoaPoint: CGPoint(x: 100, y: 500), excluding: first, primaryScreenHeight: 1000) == nil)
    }

    @Test func snapshotDistinguishesUnavailableAndEmptyAndFiltersNonWindows() throws {
        let unavailable = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: nil), currentProcessID: 99,
            windowInfo: { nil }, applicationWindows: { _ in [] }
        )
        #expect(unavailable.snapshot(primaryScreenHeight: 1000) == nil)
        let frame = CGRect(x: 0, y: 0, width: 500, height: 1000)
        let filtered = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: nil), currentProcessID: 99,
            windowInfo: { [info(id: 1, pid: 99, cocoaFrame: frame), info(id: 2, pid: 5000, cocoaFrame: frame, layer: 1), info(id: 0, pid: 5000, cocoaFrame: frame)] },
            applicationWindows: { _ in [] }
        )
        let emptySnapshot = try #require(filtered.snapshot(primaryScreenHeight: 1000))
        #expect(emptySnapshot.windows.isEmpty)
        #expect(filtered.snapshot(primaryScreenHeight: .nan) == nil)
    }

    @Test func ownApplicationIsExcludedFromPointLookupFallback() {
        let first = window(pid: 99, cocoaFrame: CGRect(x: 0, y: 0, width: 500, height: 1000))
        let second = window(pid: 99, cocoaFrame: CGRect(x: 500, y: 0, width: 500, height: 1000))
        var fallbackReads = 0
        let discovery = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: nil), currentProcessID: 99,
            windowInfo: { [] }, applicationWindows: { _ in fallbackReads += 1; return [first, second] }
        )
        #expect(discovery.window(atCocoaPoint: CGPoint(x: 750, y: 500), excluding: first, primaryScreenHeight: 1000) == nil)
        #expect(fallbackReads == 0)
    }

    @Test func pointFallbackIgnoresAXOnlyGhostAndUnavailableVisibleScene() {
        let firstFrame = CGRect(x: 0, y: 0, width: 500, height: 1000)
        let first = window(pid: 5000, cocoaFrame: firstFrame)
        let ghost = window(pid: 5000, cocoaFrame: CGRect(x: 500, y: 0, width: 500, height: 1000))
        var fallbackReads = 0
        let discovery = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: first), currentProcessID: 99,
            windowInfo: { [info(id: 1, pid: 5000, cocoaFrame: firstFrame)] },
            applicationWindows: { _ in fallbackReads += 1; return [first, ghost] }
        )
        #expect(discovery.window(atCocoaPoint: CGPoint(x: 750, y: 500), excluding: first, primaryScreenHeight: 1000) == nil)
        #expect(fallbackReads == 0)

        let unavailable = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: first), currentProcessID: 99,
            windowInfo: { nil }, applicationWindows: { _ in [first, ghost] }
        )
        #expect(unavailable.window(atCocoaPoint: CGPoint(x: 750, y: 500), excluding: first, primaryScreenHeight: 1000) == nil)
    }

    @Test func pointLookupRejectsInvalidOwnerAndStaleHitOutsideObservedFrame() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 1000)
        let invalidOwner = window(pid: 0, cocoaFrame: frame)
        let invalid = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: invalidOwner), currentProcessID: 99,
            windowInfo: { [] }, applicationWindows: { _ in [] }
        )
        #expect(invalid.window(atCocoaPoint: CGPoint(x: 250, y: 500), excluding: nil, primaryScreenHeight: 1000) == nil)
        let moved = window(pid: 5000, cocoaFrame: frame)
        let staleHit = NativeWindowDiscovery(
            accessibilityService: DiscoveryAccessibility(hit: moved), currentProcessID: 99,
            windowInfo: { [] }, applicationWindows: { _ in [] }
        )
        #expect(staleHit.window(atCocoaPoint: CGPoint(x: 750, y: 500), excluding: nil, primaryScreenHeight: 1000) == nil)
        #expect(staleHit.window(atCocoaPoint: CGPoint(x: 250, y: 500), excluding: nil, primaryScreenHeight: 1000)?.isSameWindow(as: moved) == true)
    }

    private func window(pid: pid_t, cocoaFrame: CGRect) -> WindowElement {
        window(pid: pid, backend: DiscoveryFrameAccess(frame: ScreenGeometry.cocoaToAX(cocoaRect: cocoaFrame, primaryScreenHeight: 1000)))
    }

    private func window(pid: pid_t, backend: DiscoveryFrameAccess) -> WindowElement {
        WindowElement(element: AXUIElementCreateSystemWide(), pid: pid, frameAccess: backend, identity: UUID())
    }

    private func info(id: CGWindowID, pid: pid_t, cocoaFrame: CGRect, layer: Int = 0, primaryScreenHeight: CGFloat = 1000) -> [String: Any] {
        let frame = ScreenGeometry.cocoaToAX(cocoaRect: cocoaFrame, primaryScreenHeight: primaryScreenHeight)
        return [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
                kCGWindowLayer as String: layer, kCGWindowBounds as String: frame.dictionaryRepresentation]
    }
}

private struct DiscoveryAccessibility: AccessibilityServiceProtocol {
    let hit: WindowElement?
    func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool { true }
    func getFocusedWindow() -> WindowElement? { nil }
    func getWindowUnderPoint(_ point: CGPoint) -> WindowElement? { hit }
}

/// The scripted adapter guards all mutable state; it is safe to use through the Sendable seam.
private final class DiscoveryFrameAccess: WindowFrameAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var storedFrame: CGRect?
    private var writeCount = 0
    private let acceptsWrites: Bool
    let isResizable = true

    init(frame: CGRect?, acceptsWrites: Bool = true) {
        self.storedFrame = frame
        self.acceptsWrites = acceptsWrites
    }

    var frame: CGRect? { lock.withLock { storedFrame } }
    var writes: Int { lock.withLock { writeCount } }
    func setFrame(_ frame: CGRect) -> Bool {
        guard acceptsWrites else { return false }
        lock.withLock { storedFrame = frame; writeCount += 1 }
        return true
    }
}
