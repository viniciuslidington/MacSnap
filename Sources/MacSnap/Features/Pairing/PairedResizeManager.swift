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
            // Apply final split to actual windows once on release
            pair.applyCurrentSplit(primaryScreenHeight: primaryHeight)
            state.dividerWindow.update(for: pair)
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
    public func findAdjacentWindow(atCocoaPoint point: CGPoint, excludingPid: pid_t) -> WindowElement? {
        let primaryHeight = screenService.primaryScreenHeight
        let axPoint = ScreenGeometry.cocoaPointToAX(cocoaPoint: point, primaryScreenHeight: primaryHeight)
        let myPid = ProcessInfo.processInfo.processIdentifier

        if let candidate = accessibilityService.getWindowUnderPoint(axPoint),
           candidate.pid != excludingPid && candidate.pid != myPid {
            return candidate
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
        let excludePid = windowToExclude?.pid ?? 0

        switch zone {
        // Bottom snap: look for partner at the top
        case .bottomHalf, .bottomThird, .bottomTwoThirds:
            let samplePoint = CGPoint(x: x + (w * 0.5), y: y + (h * 0.75))
            if let topPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingPid: excludePid),
               let topFrame = topPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                let availableHeight = topFrame.minY - y
                if availableHeight >= 80 {
                    let flushRect = CGRect(x: x, y: y, width: w, height: availableHeight)
                    let ratio = min(max(topFrame.height / h, 0.15), 0.85)
                    return (flushRect, topPartner, .vertical, ratio)
                }
            }

        // Top snap: look for partner at the bottom
        case .topHalf, .topThird, .topTwoThirds:
            let samplePoint = CGPoint(x: x + (w * 0.5), y: y + (h * 0.25))
            if let bottomPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingPid: excludePid),
               let bottomFrame = bottomPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                let bottomTopEdge = bottomFrame.maxY
                let availableHeight = (y + h) - bottomTopEdge
                if availableHeight >= 80 {
                    let flushRect = CGRect(x: x, y: bottomTopEdge, width: w, height: availableHeight)
                    let ratio = min(max(availableHeight / h, 0.15), 0.85)
                    return (flushRect, bottomPartner, .vertical, ratio)
                }
            }

        // Right snap: look for partner on the left
        case .rightHalf, .rightOneThird, .rightTwoThirds:
            let samplePoint = CGPoint(x: x + (w * 0.25), y: y + (h * 0.5))
            if let leftPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingPid: excludePid),
               let leftFrame = leftPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                let leftRightEdge = leftFrame.maxX
                let availableWidth = (x + w) - leftRightEdge
                if availableWidth >= 100 {
                    let flushRect = CGRect(x: leftRightEdge, y: y, width: availableWidth, height: h)
                    let ratio = min(max(leftFrame.width / w, 0.15), 0.85)
                    return (flushRect, leftPartner, .horizontal, ratio)
                }
            }

        // Left snap: look for partner on the right
        case .leftHalf, .leftOneThird, .leftThird, .leftTwoThirds:
            let samplePoint = CGPoint(x: x + (w * 0.75), y: y + (h * 0.5))
            if let rightPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingPid: excludePid),
               let rightFrame = rightPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                let rightLeftEdge = rightFrame.minX
                let availableWidth = rightLeftEdge - x
                if availableWidth >= 100 {
                    let flushRect = CGRect(x: x, y: y, width: availableWidth, height: h)
                    let ratio = min(max(availableWidth / w, 0.15), 0.85)
                    return (flushRect, rightPartner, .horizontal, ratio)
                }
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

        case .rightHalf, .rightOneThird, .rightTwoThirds:
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
        guard left.rawElement != right.rawElement else { return }
        let pair = PairedSplit(
            firstWindow: left,
            secondWindow: right,
            orientation: .horizontal,
            visibleFrame: visibleFrame,
            ratio: ratio
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
        guard top.rawElement != bottom.rawElement else { return }
        let pair = PairedSplit(
            firstWindow: top,
            secondWindow: bottom,
            orientation: .vertical,
            visibleFrame: visibleFrame,
            ratio: ratio
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
            let cgScreenY = primaryHeight - (screen.frame.origin.y + screen.frame.height)
            let cgScreenRect = CGRect(
                x: screen.frame.origin.x,
                y: cgScreenY,
                width: screen.frame.width,
                height: screen.frame.height
            )

            // Filter screen windows (Layer 0, visible, minimum size 150x150, excluding MacSnap)
            var candidates: [(pid: pid_t, name: String, frame: CGRect)] = []
            for info in windowInfoList {
                let layer = info[kCGWindowLayer as String] as? Int ?? -1
                guard layer == 0 else { continue }

                let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
                guard pid != myPid && pid != 0 else { continue }

                let name = info[kCGWindowOwnerName as String] as? String ?? ""

                if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                   let x = boundsDict["X"] as? Double,
                   let y = boundsDict["Y"] as? Double,
                   let w = boundsDict["Width"] as? Double,
                   let h = boundsDict["Height"] as? Double {
                    let frame = CGRect(x: x, y: y, width: w, height: h)
                    let center = CGPoint(x: frame.midX, y: frame.midY)

                    if cgScreenRect.contains(center) && w >= 150 && h >= 150 {
                        candidates.append((pid: pid, name: name, frame: frame))
                    }
                }
            }

            guard candidates.count >= 2 else { continue }

            // Search for the pair with greatest area or evident adjacency
            var foundPair: (first: WindowElement, second: WindowElement, orientation: SplitOrientation, ratio: CGFloat)?

            for i in 0..<candidates.count {
                if foundPair != nil { break }
                for j in (i + 1)..<candidates.count {
                    let c1 = candidates[i]
                    let c2 = candidates[j]
                    guard c1.pid != c2.pid else { continue }

                    // 1. Vertical adjacency check (Stacked: Top and Bottom)
                    let overlapX = max(0, min(c1.frame.maxX, c2.frame.maxX) - max(c1.frame.minX, c2.frame.minX))
                    let minW = min(c1.frame.width, c2.frame.width)

                    if overlapX / minW >= 0.65 {
                        let gap1 = abs(c1.frame.maxY - c2.frame.minY)
                        let gap2 = abs(c2.frame.maxY - c1.frame.minY)

                        if gap1 <= 32 {
                            // c1 is on top, c2 is on bottom
                            if let topElem = windowElement(for: c1.pid, cgFrame: c1.frame),
                               let bottomElem = windowElement(for: c2.pid, cgFrame: c2.frame) {
                                let ratio = c1.frame.height / screen.visibleFrame.height
                                foundPair = (topElem, bottomElem, .vertical, ratio)
                                break
                            }
                        } else if gap2 <= 32 {
                            // c2 is on top, c1 is on bottom
                            if let topElem = windowElement(for: c2.pid, cgFrame: c2.frame),
                               let bottomElem = windowElement(for: c1.pid, cgFrame: c1.frame) {
                                let ratio = c2.frame.height / screen.visibleFrame.height
                                foundPair = (topElem, bottomElem, .vertical, ratio)
                                break
                            }
                        }
                    }

                    // 2. Horizontal adjacency check (Side-by-side: Left and Right)
                    let overlapY = max(0, min(c1.frame.maxY, c2.frame.maxY) - max(c1.frame.minY, c2.frame.minY))
                    let minH = min(c1.frame.height, c2.frame.height)

                    if overlapY / minH >= 0.65 {
                        let gap1 = abs(c1.frame.maxX - c2.frame.minX)
                        let gap2 = abs(c2.frame.maxX - c1.frame.minX)

                        if gap1 <= 32 {
                            // c1 is on left, c2 is on right
                            if let leftElem = windowElement(for: c1.pid, cgFrame: c1.frame),
                               let rightElem = windowElement(for: c2.pid, cgFrame: c2.frame) {
                                let ratio = c1.frame.width / screen.visibleFrame.width
                                foundPair = (leftElem, rightElem, .horizontal, ratio)
                                break
                            }
                        } else if gap2 <= 32 {
                            // c2 is on left, c1 is on right
                            if let leftElem = windowElement(for: c2.pid, cgFrame: c2.frame),
                               let rightElem = windowElement(for: c1.pid, cgFrame: c1.frame) {
                                let ratio = c2.frame.width / screen.visibleFrame.width
                                foundPair = (leftElem, rightElem, .horizontal, ratio)
                                break
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
            }
        }

        return detectedPairs
    }

    /// Locates the WindowElement object corresponding to the PID and window frame.
    private func windowElement(for pid: pid_t, cgFrame: CGRect) -> WindowElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?

        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let winArray = windowsValue as? [AXUIElement] {
            for win in winArray {
                let elem = WindowElement(element: win, pid: pid)
                if let axFrame = elem.axFrame {
                    if abs(axFrame.origin.x - cgFrame.origin.x) < 40 &&
                       abs(axFrame.origin.y - cgFrame.origin.y) < 40 {
                        return elem
                    }
                }
            }
            if let first = winArray.first {
                return WindowElement(element: first, pid: pid)
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
