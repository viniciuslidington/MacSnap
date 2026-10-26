import Cocoa

/// Isolated pairing state per display, retaining history and an independent divider window.
@MainActor
public final class ScreenPairState {
    public let screenID: CGDirectDisplayID
    public var pair: PairedSplit?
    public let dividerWindow: DividerHandleWindow
    public let resizeOverlay: PairedResizeOverlayWindow

    public weak var recentLeftWindow: WindowElement?
    public weak var recentRightWindow: WindowElement?
    public weak var recentTopWindow: WindowElement?
    public weak var recentBottomWindow: WindowElement?

    public init(screenID: CGDirectDisplayID) {
        self.screenID = screenID
        self.dividerWindow = DividerHandleWindow()
        self.resizeOverlay = PairedResizeOverlayWindow()
    }

    public func clear() {
        pair = nil
        dividerWindow.orderOut(nil)
        resizeOverlay.dismiss(animated: false)
        recentLeftWindow = nil
        recentRightWindow = nil
        recentTopWindow = nil
        recentBottomWindow = nil
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
    private let accessibilityService: AccessibilityServiceProtocol

    /// Indicates whether an interactive resize divider is actively being dragged on any screen.
    public var isDraggingDivider: Bool {
        statesByScreen.values.contains { $0.dividerWindow.isDragging }
    }

    public init(
        screenService: ScreenServiceProtocol = ScreenService.shared,
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared
    ) {
        self.screenService = screenService
        self.accessibilityService = accessibilityService
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
            guard let self = self, let state = state, let pair = state.pair else { return }
            guard pair.isValid else { return }
            guard let screen = self.screenService.screens.first(where: { $0.displayID == state.screenID }) else { return }
            let (firstRect, secondRect) = pair.calculateFrames()

            let firstIcon = pair.firstWindow.appIcon
            let secondIcon = pair.secondWindow.appIcon
            let firstName = pair.firstWindow.appName
            let secondName = pair.secondWindow.appName

            state.resizeOverlay.present(
                on: screen,
                firstRect: firstRect,
                secondRect: secondRect,
                firstAppIcon: firstIcon,
                secondAppIcon: secondIcon,
                firstAppName: firstName,
                secondAppName: secondName,
                animated: true
            )
        }

        state.dividerWindow.onDividerDragged = { [weak state] cursorCoordinate in
            guard let state = state, let pair = state.pair else { return }
            guard pair.isValid else {
                state.clear()
                return
            }
            // Update ratio smoothly without firing AXUIElement resizes during drag to prevent app stutter
            pair.updateRatioOnly(from: cursorCoordinate)
            state.dividerWindow.update(for: pair)

            let (firstRect, secondRect) = pair.calculateFrames()
            state.resizeOverlay.update(firstRect: firstRect, secondRect: secondRect)
        }

        state.dividerWindow.onDividerReleased = { [weak self, weak state] in
            guard let self = self, let state = state, let pair = state.pair else { return }
            let primaryHeight = self.screenService.primaryScreenHeight
            state.resizeOverlay.dismiss(animated: true)

            // Step 1: Apply final split to actual windows once on release
            pair.applyCurrentSplit(primaryScreenHeight: primaryHeight)
            state.dividerWindow.update(for: pair)

            // Step 2: Settle pass to synchronize with real WindowServer boundaries and handle app minimum sizing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak state] in
                guard let state = state, let pair = state.pair else { return }
                guard pair.isValid else {
                    state.clear()
                    return
                }

                guard let f1 = pair.firstWindow.cocoaFrame(primaryScreenHeight: primaryHeight),
                      let f2 = pair.secondWindow.cocoaFrame(primaryScreenHeight: primaryHeight) else {
                    return
                }

                switch pair.orientation {
                case .horizontal:
                    let realSeamX = f1.maxX
                    if abs(f2.minX - realSeamX) > 4 {
                        let remainingW = max(pair.visibleFrame.maxX - realSeamX, 100)
                        let flushSecond = CGRect(
                            x: realSeamX,
                            y: pair.visibleFrame.origin.y,
                            width: remainingW,
                            height: pair.visibleFrame.height
                        )
                        pair.secondWindow.setCocoaFrame(flushSecond, primaryScreenHeight: primaryHeight)
                    }
                    let settledRatio = (realSeamX - pair.visibleFrame.origin.x) / pair.visibleFrame.width
                    pair.ratio = min(max(settledRatio, 0.15), 0.85)
                    state.dividerWindow.update(for: pair)

                case .vertical:
                    let realSeamY = f1.minY
                    if abs(f2.maxY - realSeamY) > 4 {
                        let remainingH = max(realSeamY - pair.visibleFrame.origin.y, 100)
                        let flushSecond = CGRect(
                            x: pair.visibleFrame.origin.x,
                            y: pair.visibleFrame.origin.y,
                            width: pair.visibleFrame.width,
                            height: remainingH
                        )
                        pair.secondWindow.setCocoaFrame(flushSecond, primaryScreenHeight: primaryHeight)
                    }
                    let settledRatio = (pair.visibleFrame.maxY - realSeamY) / pair.visibleFrame.height
                    pair.ratio = min(max(settledRatio, 0.15), 0.85)
                    state.dividerWindow.update(for: pair)
                }
            }
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
        let primaryHeight = screenService.primaryScreenHeight
        let cgY = primaryHeight - point.y
        let cgPoint = CGPoint(x: point.x, y: cgY)

        let opt: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(opt, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let myPid = ProcessInfo.processInfo.processIdentifier
        let pairPids: Set<pid_t> = [pair.firstWindow.pid, pair.secondWindow.pid]

        for w in infoList {
            let layer = w[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }

            let pid = w[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard pid != myPid && pid != 0 else { continue }

            let boundsDict = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero

            if bounds.insetBy(dx: -4, dy: -4).contains(cgPoint) {
                // The frontmost window at this location:
                // If it belongs to one of the paired applications, it is unoccluded!
                if pairPids.contains(pid) {
                    return false
                } else {
                    // An unrelated window is in front of the pair at this location!
                    return true
                }
            }
        }

        return false
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
        guard pair.isValid else { return false }
        guard !CFEqual(pair.firstWindow.rawElement, pair.secondWindow.rawElement) else { return false }
        let primaryHeight = screenService.primaryScreenHeight
        guard let f1 = pair.firstWindow.cocoaFrame(primaryScreenHeight: primaryHeight),
              let f2 = pair.secondWindow.cocoaFrame(primaryScreenHeight: primaryHeight) else {
            return false
        }

        switch pair.orientation {
        case .horizontal:
            // First is Left, Second is Right.
            // 1. Must be horizontally adjacent (seam gap <= 40pt)
            let seamGap = abs(f1.maxX - f2.minX)
            guard seamGap <= 40 else { return false }

            // 2. Must have significant vertical overlap
            let overlapY = max(0, min(f1.maxY, f2.maxY) - max(f1.minY, f2.minY))
            let minH = min(f1.height, f2.height)
            guard minH > 50 && (overlapY / minH) >= 0.50 else { return false }

            // 3. Must cover horizontal edges of the visible frame
            let touchesLeft = abs(f1.minX - pair.visibleFrame.origin.x) <= 50
            let touchesRight = abs(f2.maxX - pair.visibleFrame.maxX) <= 50
            guard touchesLeft && touchesRight else { return false }

            return true

        case .vertical:
            // First is Top, Second is Bottom.
            // 1. Must be vertically adjacent (Top's bottom edge f1.minY meets Bottom's top edge f2.maxY)
            let seamGap = abs(f1.minY - f2.maxY)
            guard seamGap <= 40 else { return false }

            // 2. Must have significant horizontal overlap
            let overlapX = max(0, min(f1.maxX, f2.maxX) - max(f1.minX, f2.minX))
            let minW = min(f1.width, f2.width)
            guard minW > 50 && (overlapX / minW) >= 0.50 else { return false }

            // 3. Must cover vertical edges of the visible frame
            let touchesTop = abs(f1.maxY - pair.visibleFrame.maxY) <= 50
            let touchesBottom = abs(f2.minY - pair.visibleFrame.origin.y) <= 50
            guard touchesTop && touchesBottom else { return false }

            return true
        }
    }

    /// Disbands any active pairing that contains the specified window (e.g. when dragged away).
    public func unpairWindow(_ window: WindowElement) {
        for (_, state) in statesByScreen {
            if let pair = state.pair {
                if pair.firstWindow.rawElement == window.rawElement || pair.secondWindow.rawElement == window.rawElement {
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
    public func findAdjacentWindow(
        atCocoaPoint point: CGPoint,
        excludingWindow: WindowElement? = nil
    ) -> WindowElement? {
        let primaryHeight = screenService.primaryScreenHeight
        let axPoint = ScreenGeometry.cocoaPointToAX(cocoaPoint: point, primaryScreenHeight: primaryHeight)
        let myPid = ProcessInfo.processInfo.processIdentifier

        if let candidate = accessibilityService.getWindowUnderPoint(axPoint) {
            guard candidate.pid != myPid else { return nil }
            if let excluded = excludingWindow {
                if !CFEqual(candidate.rawElement, excluded.rawElement) {
                    return candidate
                }
            } else {
                return candidate
            }
        }

        // Secondary fallback for same-app windows:
        // If systemWide hit-testing returned the excluded window or hit an overlay,
        // inspect other windows of the same application containing the sample point.
        if let excluded = excludingWindow {
            let appElement = AXUIElementCreateApplication(excluded.pid)
            var windowsValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
               let winArray = windowsValue as? [AXUIElement] {
                for win in winArray {
                    guard !CFEqual(win, excluded.rawElement) else { continue }
                    let otherElem = WindowElement(element: win, pid: excluded.pid)
                    if let frame = otherElem.cocoaFrame(primaryScreenHeight: primaryHeight),
                       frame.contains(point) {
                        return otherElem
                    }
                }
            }
        }

        return nil
    }

    /// Calculates the exact remaining area if a partner window is already positioned on the opposite side,
    /// avoiding overlap even when the partner window has a custom size or minimum height (e.g., Xcode).
    public func calculateFlushTargetRect(
        for zone: SnapZone,
        screen: NSScreen,
        windowToExclude: WindowElement?
    ) -> (targetRect: CGRect, partner: WindowElement, orientation: SplitOrientation, ratio: CGFloat)? {
        let visibleFrame = screen.visibleFrame
        let w = visibleFrame.width
        let h = visibleFrame.height
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let primaryHeight = screenService.primaryScreenHeight
        let defaultTarget = zone.targetRect(for: visibleFrame)

        switch zone {
        // Bottom snaps: look for partner immediately above default target
        case .bottomHalf, .bottomThird, .bottomTwoThirds:
            let sampleY = min(defaultTarget.maxY + 30.0, y + h - 20.0)
            let samplePoint = CGPoint(x: defaultTarget.midX, y: sampleY)
            if let topPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingWindow: windowToExclude),
               let topFrame = topPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                // Partner must be anchored to the top screen boundary
                guard abs(topFrame.maxY - (y + h)) <= 40 else { break }
                // Partner must reach or intrude into the default target area boundary
                guard topFrame.minY <= defaultTarget.maxY + 40 else { break }
                let availableHeight = topFrame.minY - y
                if availableHeight >= 80 {
                    let flushRect = CGRect(x: defaultTarget.minX, y: y, width: defaultTarget.width, height: availableHeight)
                    let ratio = min(max(topFrame.height / h, 0.15), 0.85)
                    return (flushRect, topPartner, .vertical, ratio)
                }
            }

        // Top snaps: look for partner immediately below default target
        case .topHalf, .topThird, .topTwoThirds:
            let sampleY = max(defaultTarget.minY - 30.0, y + 20.0)
            let samplePoint = CGPoint(x: defaultTarget.midX, y: sampleY)
            if let bottomPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingWindow: windowToExclude),
               let bottomFrame = bottomPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                // Partner must be anchored to the bottom screen boundary
                guard abs(bottomFrame.minY - y) <= 40 else { break }
                // Partner must reach or intrude into the default target area boundary
                guard bottomFrame.maxY >= defaultTarget.minY - 40 else { break }
                let bottomTopEdge = bottomFrame.maxY
                let availableHeight = (y + h) - bottomTopEdge
                if availableHeight >= 80 {
                    let flushRect = CGRect(x: defaultTarget.minX, y: bottomTopEdge, width: defaultTarget.width, height: availableHeight)
                    let ratio = min(max(availableHeight / h, 0.15), 0.85)
                    return (flushRect, bottomPartner, .vertical, ratio)
                }
            }

        // Right snaps: look for partner immediately to the left of default target
        case .rightHalf, .rightOneThird, .rightThird, .rightTwoThirds:
            let sampleX = max(defaultTarget.minX - 30.0, x + 20.0)
            let samplePoint = CGPoint(x: sampleX, y: defaultTarget.midY)
            if let leftPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingWindow: windowToExclude),
               let leftFrame = leftPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                // Partner must be anchored to the left screen boundary
                guard abs(leftFrame.minX - x) <= 40 else { break }
                // Partner must reach or intrude into the default target area boundary
                guard leftFrame.maxX >= defaultTarget.minX - 40 else { break }
                let leftRightEdge = leftFrame.maxX
                let availableWidth = (x + w) - leftRightEdge
                if availableWidth >= 100 {
                    let flushRect = CGRect(x: leftRightEdge, y: defaultTarget.minY, width: availableWidth, height: defaultTarget.height)
                    let ratio = min(max(leftFrame.width / w, 0.15), 0.85)
                    return (flushRect, leftPartner, .horizontal, ratio)
                }
            }

        // Left snaps: look for partner immediately to the right of default target
        case .leftHalf, .leftOneThird, .leftThird, .leftTwoThirds:
            let sampleX = min(defaultTarget.maxX + 30.0, x + w - 20.0)
            let samplePoint = CGPoint(x: sampleX, y: defaultTarget.midY)
            if let rightPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingWindow: windowToExclude),
               let rightFrame = rightPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                // Partner must be anchored to the right screen boundary
                guard abs(rightFrame.maxX - (x + w)) <= 40 else { break }
                // Partner must reach or intrude into the default target area boundary
                guard rightFrame.minX <= defaultTarget.maxX + 40 else { break }
                let rightLeftEdge = rightFrame.minX
                let availableWidth = rightLeftEdge - x
                if availableWidth >= 100 {
                    let flushRect = CGRect(x: x, y: defaultTarget.minY, width: availableWidth, height: defaultTarget.height)
                    let ratio = min(max(availableWidth / w, 0.15), 0.85)
                    return (flushRect, rightPartner, .horizontal, ratio)
                }
            }

        // Center third snap: dock flush between left and right neighbors if they exist
        case .centerThird:
            let leftSample = CGPoint(x: max(defaultTarget.minX - 30.0, x + 20.0), y: defaultTarget.midY)
            let leftNeighbor = findAdjacentWindow(atCocoaPoint: leftSample, excludingWindow: windowToExclude)
            var leftEdge = defaultTarget.minX
            if let neighbor = leftNeighbor, let frame = neighbor.cocoaFrame(primaryScreenHeight: primaryHeight), abs(frame.minX - x) <= 40 {
                leftEdge = frame.maxX
            }

            let rightSample = CGPoint(x: min(defaultTarget.maxX + 30.0, x + w - 20.0), y: defaultTarget.midY)
            let rightNeighbor = findAdjacentWindow(atCocoaPoint: rightSample, excludingWindow: windowToExclude)
            var rightEdge = defaultTarget.maxX
            if let neighbor = rightNeighbor, let frame = neighbor.cocoaFrame(primaryScreenHeight: primaryHeight), abs(frame.maxX - (x + w)) <= 40 {
                rightEdge = frame.minX
            }

            let targetWidth = max(rightEdge - leftEdge, 100)
            let flushRect = CGRect(x: leftEdge, y: defaultTarget.minY, width: targetWidth, height: defaultTarget.height)
            if let leftP = leftNeighbor {
                let ratio = min(max((leftEdge - x) / w, 0.15), 0.85)
                return (flushRect, leftP, .horizontal, ratio)
            } else if let rightP = rightNeighbor {
                let ratio = min(max((rightEdge - x) / w, 0.15), 0.85)
                return (flushRect, rightP, .horizontal, ratio)
            }

        default:
            break
        }

        return nil
    }

    /// Registers a newly snapped window and activates the divider if an opposite partner is present on that display.
    public func registerSnap(window: WindowElement, zone: SnapZone, screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let screenState = state(for: screen)

        // 1. Attempt to dynamically pair using the detected partner at the intersection on this display
        if let flush = calculateFlushTargetRect(for: zone, screen: screen, windowToExclude: window) {
            if flush.orientation == .vertical {
                if zone == .topHalf || zone == .topThird || zone == .topTwoThirds {
                    screenState.recentTopWindow = window
                    screenState.recentBottomWindow = flush.partner
                    createVerticalPair(top: window, bottom: flush.partner, ratio: flush.ratio, visibleFrame: visibleFrame, in: screenState)
                } else {
                    screenState.recentTopWindow = flush.partner
                    screenState.recentBottomWindow = window
                    createVerticalPair(top: flush.partner, bottom: window, ratio: flush.ratio, visibleFrame: visibleFrame, in: screenState)
                }
            } else {
                if zone == .leftHalf || zone == .leftOneThird || zone == .leftThird || zone == .leftTwoThirds {
                    screenState.recentLeftWindow = window
                    screenState.recentRightWindow = flush.partner
                    createHorizontalPair(left: window, right: flush.partner, ratio: flush.ratio, visibleFrame: visibleFrame, in: screenState)
                } else {
                    screenState.recentLeftWindow = flush.partner
                    screenState.recentRightWindow = window
                    createHorizontalPair(left: flush.partner, right: window, ratio: flush.ratio, visibleFrame: visibleFrame, in: screenState)
                }
            }
            return
        }

        // 2. Recent history fallback isolated to this display
        switch zone {
        case .leftHalf, .leftOneThird, .leftThird, .leftTwoThirds:
            screenState.recentLeftWindow = window
            if let right = screenState.recentRightWindow {
                createHorizontalPair(left: window, right: right, ratio: 0.5, visibleFrame: visibleFrame, in: screenState)
            }

        case .rightHalf, .rightOneThird, .rightThird, .rightTwoThirds:
            screenState.recentRightWindow = window
            if let left = screenState.recentLeftWindow {
                createHorizontalPair(left: left, right: window, ratio: 0.5, visibleFrame: visibleFrame, in: screenState)
            }

        case .topHalf, .topThird, .topTwoThirds:
            screenState.recentTopWindow = window
            if let bottom = screenState.recentBottomWindow {
                createVerticalPair(top: window, bottom: bottom, ratio: 0.5, visibleFrame: visibleFrame, in: screenState)
            }

        case .bottomHalf, .bottomThird, .bottomTwoThirds:
            screenState.recentBottomWindow = window
            if let top = screenState.recentTopWindow {
                createVerticalPair(top: top, bottom: window, ratio: 0.5, visibleFrame: visibleFrame, in: screenState)
            }

        case .centerThird:
            // Center third does not form a binary 50/50 pair across the screen
            screenState.clear()

        case .maximize:
            screenState.clear()

        default:
            screenState.clear()
        }
    }

    private func createHorizontalPair(
        left: WindowElement,
        right: WindowElement,
        ratio: CGFloat,
        visibleFrame: CGRect,
        in screenState: ScreenPairState
    ) {
        guard !CFEqual(left.rawElement, right.rawElement) else { return }
        let primaryHeight = screenService.primaryScreenHeight
        guard let leftFrame = left.cocoaFrame(primaryScreenHeight: primaryHeight),
              let rightFrame = right.cocoaFrame(primaryScreenHeight: primaryHeight) else {
            return
        }

        // Must be genuinely adjacent horizontally (left's right edge meets right's left edge)
        let gap = abs(leftFrame.maxX - rightFrame.minX)
        guard gap <= 32 else {
            return
        }

        let overlapY = max(0, min(leftFrame.maxY, rightFrame.maxY) - max(leftFrame.minY, rightFrame.minY))
        let minH = min(leftFrame.height, rightFrame.height)
        guard minH > 50 && (overlapY / minH) >= 0.50 else { return }

        // Compute actual ratio based on where the real seam is
        let actualRatio = min(max((leftFrame.maxX - visibleFrame.origin.x) / visibleFrame.width, 0.15), 0.85)

        let pair = PairedSplit(
            firstWindow: left,
            secondWindow: right,
            orientation: .horizontal,
            visibleFrame: visibleFrame,
            ratio: actualRatio
        )
        screenState.pair = pair
        screenState.dividerWindow.update(for: pair)
    }

    private func createVerticalPair(
        top: WindowElement,
        bottom: WindowElement,
        ratio: CGFloat,
        visibleFrame: CGRect,
        in screenState: ScreenPairState
    ) {
        guard !CFEqual(top.rawElement, bottom.rawElement) else { return }
        let primaryHeight = screenService.primaryScreenHeight
        guard let topFrame = top.cocoaFrame(primaryScreenHeight: primaryHeight),
              let bottomFrame = bottom.cocoaFrame(primaryScreenHeight: primaryHeight) else {
            return
        }

        // Top's bottom edge (topFrame.minY) meets Bottom's top edge (bottomFrame.maxY)
        let gap = abs(topFrame.minY - bottomFrame.maxY)
        guard gap <= 32 else {
            return
        }

        let overlapX = max(0, min(topFrame.maxX, bottomFrame.maxX) - max(topFrame.minX, bottomFrame.minX))
        let minW = min(topFrame.width, bottomFrame.width)
        guard minW > 50 && (overlapX / minW) >= 0.50 else { return }

        let actualRatio = min(max((visibleFrame.maxY - topFrame.minY) / visibleFrame.height, 0.15), 0.85)

        let pair = PairedSplit(
            firstWindow: top,
            secondWindow: bottom,
            orientation: .vertical,
            visibleFrame: visibleFrame,
            ratio: actualRatio
        )
        screenState.pair = pair
        screenState.dividerWindow.update(for: pair)
    }

    /// Forces explicit pairing of two known windows on the specified screen.
    public func pair(
        first: WindowElement,
        second: WindowElement,
        orientation: SplitOrientation,
        on screen: NSScreen,
        ratio: CGFloat = 0.5
    ) {
        let screenState = state(for: screen)
        let pair = PairedSplit(
            firstWindow: first,
            secondWindow: second,
            orientation: orientation,
            visibleFrame: screen.visibleFrame,
            ratio: ratio
        )
        screenState.pair = pair
        let primaryHeight = screenService.primaryScreenHeight
        pair.applyCurrentSplit(primaryScreenHeight: primaryHeight)
        screenState.dividerWindow.update(for: pair)
    }

    /// Automatically scans the specified display (or all displays) searching for two open windows
    /// that share a common boundary (side-by-side or stacked) and connects the interactive divider between them.
    @discardableResult
    public func autoDetectAdjacentWindows(on targetScreen: NSScreen? = nil) -> [PairedSplit] {
        let screensToScan = targetScreen != nil ? [targetScreen!] : screenService.screens
        var detectedPairs: [PairedSplit] = []

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return detectedPairs
        }

        let myPid = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = screenService.primaryScreenHeight

        for screen in screensToScan {
            let screenState = state(for: screen)

            // Filter screen windows (Layer 0, visible, minimum size 150x150, excluding MacSnap)
            // Stored in Cocoa bottom-left coordinates for consistent geometry calculations across all monitors
            var candidates: [(windowID: CGWindowID, pid: pid_t, name: String, frame: CGRect)] = []
            for info in windowInfoList {
                let layer = info[kCGWindowLayer as String] as? Int ?? -1
                guard layer == 0 else { continue }

                let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
                guard pid != myPid && pid != 0 else { continue }

                let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
                let name = info[kCGWindowOwnerName as String] as? String ?? ""

                if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                   let x = boundsDict["X"] as? Double,
                   let y = boundsDict["Y"] as? Double,
                   let w = boundsDict["Width"] as? Double,
                   let h = boundsDict["Height"] as? Double {
                    let cocoaY = primaryHeight - y - h
                    let cocoaFrame = CGRect(x: x, y: cocoaY, width: w, height: h)
                    let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)

                    if screen.frame.contains(center) && w >= 150 && h >= 150 {
                        candidates.append((windowID: windowID, pid: pid, name: name, frame: cocoaFrame))
                    }
                }
            }

            guard candidates.count >= 2 else {
                screenState.clear()
                continue
            }

            // Search for the pair with greatest area or evident adjacency
            var foundPair: (first: WindowElement, second: WindowElement, orientation: SplitOrientation, ratio: CGFloat)?

            for i in 0..<candidates.count {
                if foundPair != nil { break }
                for j in (i + 1)..<candidates.count {
                    let c1 = candidates[i]
                    let c2 = candidates[j]
                    guard c1.windowID != c2.windowID else { continue }

                    // 1. Vertical adjacency check (Stacked: Top and Bottom)
                    let overlapX = max(0, min(c1.frame.maxX, c2.frame.maxX) - max(c1.frame.minX, c2.frame.minX))
                    let minW = min(c1.frame.width, c2.frame.width)

                    if overlapX / minW >= 0.50 {
                        // In Cocoa coordinates, Top window has higher Y than Bottom window
                        let gap1 = abs(c1.frame.minY - c2.frame.maxY)
                        let gap2 = abs(c2.frame.minY - c1.frame.maxY)

                        if gap1 <= 32 {
                            // c1 is on top, c2 is on bottom
                            let topTouches = abs(c1.frame.maxY - screen.visibleFrame.maxY) <= 50
                            let bottomTouches = abs(c2.frame.minY - screen.visibleFrame.origin.y) <= 50
                            if topTouches && bottomTouches {
                                if let topElem = windowElement(for: c1.pid, cocoaFrame: c1.frame),
                                   let bottomElem = windowElement(for: c2.pid, cocoaFrame: c2.frame),
                                   !CFEqual(topElem.rawElement, bottomElem.rawElement) {
                                    let ratio = c1.frame.height / screen.visibleFrame.height
                                    foundPair = (topElem, bottomElem, .vertical, ratio)
                                    break
                                }
                            }
                        } else if gap2 <= 32 {
                            // c2 is on top, c1 is on bottom
                            let topTouches = abs(c2.frame.maxY - screen.visibleFrame.maxY) <= 50
                            let bottomTouches = abs(c1.frame.minY - screen.visibleFrame.origin.y) <= 50
                            if topTouches && bottomTouches {
                                if let topElem = windowElement(for: c2.pid, cocoaFrame: c2.frame),
                                   let bottomElem = windowElement(for: c1.pid, cocoaFrame: c1.frame),
                                   !CFEqual(topElem.rawElement, bottomElem.rawElement) {
                                    let ratio = c2.frame.height / screen.visibleFrame.height
                                    foundPair = (topElem, bottomElem, .vertical, ratio)
                                    break
                                }
                            }
                        }
                    }

                    // 2. Horizontal adjacency check (Side-by-side: Left and Right)
                    let overlapY = max(0, min(c1.frame.maxY, c2.frame.maxY) - max(c1.frame.minY, c2.frame.minY))
                    let minH = min(c1.frame.height, c2.frame.height)

                    if overlapY / minH >= 0.50 {
                        let gap1 = abs(c1.frame.maxX - c2.frame.minX)
                        let gap2 = abs(c2.frame.maxX - c1.frame.minX)

                        if gap1 <= 32 {
                            // c1 is on left, c2 is on right
                            let leftTouches = abs(c1.frame.minX - screen.visibleFrame.origin.x) <= 50
                            let rightTouches = abs(c2.frame.maxX - screen.visibleFrame.maxX) <= 50
                            if leftTouches && rightTouches {
                                if let leftElem = windowElement(for: c1.pid, cocoaFrame: c1.frame),
                                   let rightElem = windowElement(for: c2.pid, cocoaFrame: c2.frame),
                                   !CFEqual(leftElem.rawElement, rightElem.rawElement) {
                                    let ratio = c1.frame.width / screen.visibleFrame.width
                                    foundPair = (leftElem, rightElem, .horizontal, ratio)
                                    break
                                }
                            }
                        } else if gap2 <= 32 {
                            // c2 is on left, c1 is on right
                            let leftTouches = abs(c2.frame.minX - screen.visibleFrame.origin.x) <= 50
                            let rightTouches = abs(c1.frame.maxX - screen.visibleFrame.maxX) <= 50
                            if leftTouches && rightTouches {
                                if let leftElem = windowElement(for: c2.pid, cocoaFrame: c2.frame),
                                   let rightElem = windowElement(for: c1.pid, cocoaFrame: c1.frame),
                                   !CFEqual(leftElem.rawElement, rightElem.rawElement) {
                                    let ratio = c2.frame.width / screen.visibleFrame.width
                                    foundPair = (leftElem, rightElem, .horizontal, ratio)
                                    break
                                }
                            }
                        }
                    }
                }
            }

            if let found = foundPair {
                let clampedRatio = min(max(found.ratio, 0.15), 0.85)
                let pair = PairedSplit(
                    firstWindow: found.first,
                    secondWindow: found.second,
                    orientation: found.orientation,
                    visibleFrame: screen.visibleFrame,
                    ratio: clampedRatio
                )
                screenState.pair = pair
                screenState.dividerWindow.update(for: pair)
                detectedPairs.append(pair)
            } else {
                screenState.clear()
            }
        }

        return detectedPairs
    }

    /// Locates the WindowElement object corresponding to the PID and Cocoa window frame.
    private func windowElement(for pid: pid_t, cocoaFrame: CGRect) -> WindowElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        let primaryHeight = screenService.primaryScreenHeight

        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let winArray = windowsValue as? [AXUIElement] {
            var bestMatch: WindowElement?
            var smallestDistance: CGFloat = .greatestFiniteMagnitude

            for win in winArray {
                let elem = WindowElement(element: win, pid: pid)
                if let elemFrame = elem.cocoaFrame(primaryScreenHeight: primaryHeight) {
                    let dist = abs(elemFrame.origin.x - cocoaFrame.origin.x) +
                               abs(elemFrame.origin.y - cocoaFrame.origin.y) +
                               abs(elemFrame.width - cocoaFrame.width) +
                               abs(elemFrame.height - cocoaFrame.height)
                    if dist < smallestDistance {
                        smallestDistance = dist
                        bestMatch = elem
                    }
                }
            }
            if let match = bestMatch, smallestDistance < 60 {
                return match
            }
        }

        return nil
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
