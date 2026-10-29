import Cocoa

/// Isolated pair, resize lifetime and presentation for one display.
@MainActor
public final class ScreenPairState {
    public let screenID: CGDirectDisplayID
    public var pair: PairedSplit? {
        didSet {
            guard oldValue !== pair else { return }
            resizeSession?.cancel()
            resizeSession = nil
        }
    }
    var resizeSession: PairedResizeSession?
    public let dividerWindow: DividerHandleWindow
    public let resizeOverlay: PairedResizeOverlayWindow

    public init(screenID: CGDirectDisplayID) {
        self.screenID = screenID
        self.dividerWindow = DividerHandleWindow()
        self.resizeOverlay = PairedResizeOverlayWindow()
    }

    public func clear() {
        resizeSession?.cancel()
        resizeSession = nil
        pair = nil
        dividerWindow.orderOut(nil)
        resizeOverlay.dismiss(animated: false)
    }
}

/// Manages side-by-side (horizontal) or stacked (vertical) paired windows and the interactive central divider.
/// Supports multiple simultaneous displays by maintaining active pairs on each screen independently.
@MainActor
public final class PairedResizeManager {
    public static let shared = PairedResizeManager()

    /// Pairing states indexed by numeric display ID (displayID)
    private var statesByScreen: [CGDirectDisplayID: ScreenPairState] = [:]
    private let screenService: ScreenServiceProtocol
    private let windowDiscovery: any WindowDiscovering
    private let scheduler: any ActionScheduling
    private let isMasterEnabled: @MainActor () -> Bool
    private var observedPrimaryScreenHeight: CGFloat

    private static let dividerEnabledKey = "MacSnap.isDividerEnabled"

    /// Controls whether the interactive paired window divider ("swiper") is enabled.
    public var isDividerEnabled: Bool = (UserDefaults.standard.object(forKey: dividerEnabledKey) as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(isDividerEnabled, forKey: Self.dividerEnabledKey)
            if !isDividerEnabled {
                clearPairing()
            } else if isMasterEnabled() {
                autoDetectAdjacentWindows()
            }
        }
    }

    /// Indicates whether an interactive resize divider is actively being dragged on any screen.
    public var isDraggingDivider: Bool {
        statesByScreen.values.contains { $0.dividerWindow.isDragging }
    }

    public init(
        screenService: ScreenServiceProtocol = ScreenService.shared,
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared,
        scheduler: any ActionScheduling = MainActorScheduler.shared,
        windowDiscovery: (any WindowDiscovering)? = nil,
        isMasterEnabled: @escaping @MainActor () -> Bool = { GlobalEventMonitor.shared.isMasterEnabled }
    ) {
        self.screenService = screenService
        self.windowDiscovery = windowDiscovery ?? NativeWindowDiscovery(accessibilityService: accessibilityService)
        self.scheduler = scheduler
        self.isMasterEnabled = isMasterEnabled
        self.observedPrimaryScreenHeight = screenService.primaryScreenHeight
    }

    /// Returns or initializes the dedicated pairing state for the specified screen.
    public func state(for screen: NSScreen) -> ScreenPairState {
        let id = screen.displayID
        if let existing = statesByScreen[id] {
            return existing
        }
        let newState = ScreenPairState(screenID: id)
        setupDividerCallbacks(for: newState)
        statesByScreen[id] = newState
        return newState
    }

    private func setupDividerCallbacks(for state: ScreenPairState) {
        state.dividerWindow.onDividerDragStarted = { [weak self, weak state] in
            guard let self, let state, let pair = state.pair else { return }
            guard let screen = self.screenService.screens.first(where: { $0.displayID == state.screenID }) else { return }
            state.resizeSession?.cancel()
            let primaryHeight = self.screenService.primaryScreenHeight
            let session = PairedResizeSession(
                pair: pair,
                primaryScreenHeight: primaryHeight,
                presentation: ScreenPairResizePresentation(state: state, screen: screen),
                scheduler: self.scheduler,
                isCurrent: { [weak self, weak state, weak pair] in
                    guard let self, let state, let pair,
                          self.screenService.primaryScreenHeight == primaryHeight,
                          let currentScreen = self.screenService.screens.first(where: { $0.displayID == state.screenID }),
                          currentScreen.visibleFrame == pair.visibleFrame else { return false }
                    return state.pair === pair
                },
                onInvalidated: { [weak state] in state?.clear() }
            )
            state.resizeSession = session
            session.begin()
        }

        state.dividerWindow.onDividerDragged = { [weak state] coordinate in
            state?.resizeSession?.update(to: coordinate)
        }

        state.dividerWindow.onDividerReleased = { [weak state] in
            state?.resizeSession?.finish()
        }

        state.dividerWindow.validatePair = { [weak self, weak state] in
            guard let self = self, let state = state, let pair = state.pair else { return false }
            return self.isPairValidAndAdjacent(pair)
        }

        state.dividerWindow.isOccludedAtPoint = { [weak self, weak state] point in
            guard let self = self, let state = state, let pair = state.pair else { return false }
            return self.isPairOccluded(atCocoaPoint: point, for: pair)
        }

        state.dividerWindow.onInvalidPairDetected = { [weak state] in
            state?.clear()
        }
    }

    /// Determines whether the seam at the given Cocoa screen point is occluded by an unrelated frontmost window.
    public func isPairOccluded(atCocoaPoint point: CGPoint, for pair: PairedSplit) -> Bool {
        guard let snapshot = windowDiscovery.snapshot(primaryScreenHeight: screenService.primaryScreenHeight) else { return true }
        return snapshot.isOccluded(at: point, pairedFirst: pair.firstWindow, pairedSecond: pair.secondWindow)
    }

    /// Handles application activation to immediately suppress dividers when an unrelated app becomes active.
    public func handleApplicationActivated(_ app: NSRunningApplication) {
        for (_, state) in statesByScreen {
            if let pair = state.pair {
                if app.processIdentifier != pair.firstWindow.pid && app.processIdentifier != pair.secondWindow.pid {
                    state.dividerWindow.hideDividerImmediately()
                }
            }
        }
    }

    /// Validates in real time whether both windows in a pair are still valid, accessible,
    /// and physically adjacent along their shared seam on screen.
    public func isPairValidAndAdjacent(_ pair: PairedSplit) -> Bool {
        guard !pair.firstWindow.isSameWindow(as: pair.secondWindow),
              let first = pair.firstWindow.cocoaFrame(primaryScreenHeight: screenService.primaryScreenHeight),
              let second = pair.secondWindow.cocoaFrame(primaryScreenHeight: screenService.primaryScreenHeight),
              let split = PairGeometry.split(first: first, second: second, in: pair.visibleFrame, gapTolerance: 40) else { return false }
        return split.orientation == pair.orientation && split.firstIsLeading
    }

    /// Disbands any active pairing that contains the specified window (e.g. when dragged away).
    public func unpairWindow(_ window: WindowElement) {
        for (_, state) in statesByScreen {
            if let pair = state.pair {
                if pair.firstWindow.isSameWindow(as: window) || pair.secondWindow.isSameWindow(as: window) {
                    state.clear()
                }
            }
        }
    }

    /// Returns the active pair on the screen under the cursor (or the first available for compatibility).
    public var activePair: PairedSplit? {
        if let currentScreen = screenService.screenContaining(point: NSEvent.mouseLocation) {
            return statesByScreen[currentScreen.displayID]?.pair
        }
        return statesByScreen.values.compactMap { $0.pair }.first
    }

    /// Returns all active pairs maintained across all connected displays.
    public var activePairs: [PairedSplit] {
        return statesByScreen.values.compactMap { $0.pair }
    }

    /// Actively searches whether an open window already exists on the opposite side to connect the pair immediately.
    public func findAdjacentWindow(atCocoaPoint point: CGPoint, excludingWindow: WindowElement? = nil) -> WindowElement? {
        windowDiscovery.window(atCocoaPoint: point, excluding: excludingWindow, primaryScreenHeight: screenService.primaryScreenHeight)
    }

    /// Registers a newly snapped window and activates the divider if an opposite partner is present on that display.
    public func registerSnap(window: WindowElement, zone: SnapZone, screen: NSScreen) {
        guard isDividerEnabled && isMasterEnabled() else { return }
        let state = state(for: screen)
        switch zone {
        case .centerThird, .middleThird, .maximize,
             .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            state.clear()
            return
        default: break
        }
        guard let snapshot = windowDiscovery.snapshot(primaryScreenHeight: screenService.primaryScreenHeight) else { return }
        for observation in snapshot.windows where screen.frame.contains(CGPoint(x: observation.frame.midX, y: observation.frame.midY)) {
            guard let other = snapshot.element(for: observation), !window.isSameWindow(as: other) else { continue }
            if adoptPair(window, other, visibleFrame: screen.visibleFrame, in: state) != nil { return }
        }
        state.clear()
    }

    /// Forces explicit pairing of two known windows on the specified screen.
    public func pair(
        first: WindowElement,
        second: WindowElement,
        orientation: SplitOrientation,
        on screen: NSScreen,
        ratio: CGFloat = 0.5
    ) {
        guard isDividerEnabled && isMasterEnabled() else { return }
        let screenState = state(for: screen)
        let pair = PairedSplit(
            firstWindow: first,
            secondWindow: second,
            orientation: orientation,
            visibleFrame: screen.visibleFrame,
            ratio: ratio
        )
        let primaryHeight = screenService.primaryScreenHeight
        guard !first.isSameWindow(as: second),
              pair.applyCurrentSplit(primaryScreenHeight: primaryHeight),
              adoptPair(first, second, visibleFrame: screen.visibleFrame, in: screenState) != nil else {
            screenState.clear()
            return
        }
    }

    /// Retires captured resize lifetimes before observing windows on the current displays.
    public func handleScreenConfigurationChange() {
        autoDetectAdjacentWindows()
    }

    private func purgeStaleScreenStates() {
        let connectedScreens = screenService.screens
        let primaryHeight = screenService.primaryScreenHeight
        let referenceOriginChanged = primaryHeight != observedPrimaryScreenHeight
        observedPrimaryScreenHeight = primaryHeight
        let staleIDs = statesByScreen.compactMap { id, state -> CGDirectDisplayID? in
            // AX's top-left reference changes for every display when this height changes,
            // including secondary displays whose own Cocoa visibleFrame is unchanged.
            if referenceOriginChanged { return id }
            guard let screen = connectedScreens.first(where: { $0.displayID == id }) else { return id }
            if let pair = state.pair, pair.visibleFrame != screen.visibleFrame { return id }
            return nil
        }
        for id in staleIDs {
            statesByScreen.removeValue(forKey: id)?.clear()
        }
    }

    /// Automatically scans the specified display (or all displays) searching for two open windows
    /// that share a common boundary (side-by-side or stacked) and connects the interactive divider between them.
    @discardableResult
    public func autoDetectAdjacentWindows(on targetScreen: NSScreen? = nil) -> [PairedSplit] {
        // Cleanup is unconditional: paused state and unavailable observations must not
        // keep a pending operation alive for a disconnected or reconfigured display.
        purgeStaleScreenStates()
        guard isDividerEnabled && isMasterEnabled(),
              let snapshot = windowDiscovery.snapshot(primaryScreenHeight: screenService.primaryScreenHeight) else { return [] }
        var result: [PairedSplit] = []
        let connectedScreens = screenService.screens
        let screensToScan = targetScreen.map { target in
            connectedScreens.filter { $0.displayID == target.displayID }
        } ?? connectedScreens
        for screen in screensToScan {
            let state = state(for: screen)
            // An activation notification must not replace a pair during its active resize or settlement.
            if let session = state.resizeSession, session.phase == .dragging || session.phase == .settling { continue }
            let candidates = snapshot.windows.filter {
                $0.frame.width >= 150 && $0.frame.height >= 150 && screen.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
            }
            var found: PairedSplit?
            for (index, first) in candidates.enumerated() {
                for second in candidates.dropFirst(index + 1) {
                    guard PairGeometry.split(first: first.frame, second: second.frame, in: screen.visibleFrame) != nil,
                          let firstElement = snapshot.element(for: first),
                          let secondElement = snapshot.element(for: second) else { continue }
                    found = adoptPair(firstElement, secondElement, visibleFrame: screen.visibleFrame, in: state)
                    if found != nil { break }
                }
                if found != nil { break }
            }
            if let found { result.append(found) } else { state.clear() }
        }
        return result
    }

    private func adoptPair(_ first: WindowElement, _ second: WindowElement, visibleFrame: CGRect, in state: ScreenPairState) -> PairedSplit? {
        guard !first.isSameWindow(as: second),
              let firstFrame = first.cocoaFrame(primaryScreenHeight: screenService.primaryScreenHeight),
              let secondFrame = second.cocoaFrame(primaryScreenHeight: screenService.primaryScreenHeight),
              let split = PairGeometry.split(first: firstFrame, second: secondFrame, in: visibleFrame) else { return nil }
        let pair = PairedSplit(firstWindow: split.firstIsLeading ? first : second,
                               secondWindow: split.firstIsLeading ? second : first,
                               orientation: split.orientation, visibleFrame: visibleFrame, ratio: split.ratio)
        state.pair = pair
        state.dividerWindow.update(for: pair)
        return pair
    }

    /// Removes the divider bar and disbands active pairing (for a specific display or all displays).
    public func clearPairing(for screen: NSScreen? = nil) {
        if let screen = screen {
            statesByScreen[screen.displayID]?.clear()
            statesByScreen.removeValue(forKey: screen.displayID)
        } else {
            for (_, state) in statesByScreen {
                state.clear()
            }
            statesByScreen.removeAll()
        }
    }
}
