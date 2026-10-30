import Cocoa
import CoreGraphics

/// Native event capture and presentation for window dragging.
/// Gesture recognition and snap placement own their state behind separate interfaces.
@MainActor
public final class GlobalEventMonitor: EventMonitoringProtocol {
    public static let shared = GlobalEventMonitor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapContext: EventTapContext?
    private var monitoringGeneration: UInt64 = 0
    private var recognition = DragRecognition<WindowElement>()
    private var activeZone: SnapZone?
    private var activeScreen: NSScreen?
    private var isZoneFromLayoutBar = false

    /// Used by application shutdown to avoid interrupting a window gesture.
    var hasActiveWindowInteraction: Bool { recognition.isDragging }

    private static let masterEnabledKey = "MacSnap.isMasterEnabled"
    private static let topSnapBarEnabledKey = "MacSnap.isTopSnapBarEnabled"
    private static let edgeSnapEnabledKey = "MacSnap.isEdgeSnapEnabled"

    public var isMasterEnabled: Bool = (UserDefaults.standard.object(forKey: masterEnabledKey) as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(isMasterEnabled, forKey: Self.masterEnabledKey)
            if !isMasterEnabled {
                resetDragInteraction(ignoringUntilRelease: recognition.window != nil || recognition.isIgnored)
                pairingManager.clearPairing()
            } else {
                pairingManager.autoDetectAdjacentWindows()
            }
        }
    }

    public var isTopSnapBarEnabled: Bool = (UserDefaults.standard.object(forKey: topSnapBarEnabledKey) as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(isTopSnapBarEnabled, forKey: Self.topSnapBarEnabledKey)
            if !isTopSnapBarEnabled {
                snapLayoutBar.dismiss(animated: false)
                snapEngine.cancelPendingOperations()
                if isZoneFromLayoutBar { clearSnapSelection() }
            }
        }
    }

    public var isEdgeSnapEnabled: Bool = (UserDefaults.standard.object(forKey: edgeSnapEnabledKey) as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(isEdgeSnapEnabled, forKey: Self.edgeSnapEnabledKey)
            if !isEdgeSnapEnabled {
                snapEngine.cancelPendingOperations()
                if !isZoneFromLayoutBar { clearSnapSelection() }
            }
        }
    }

    private let screenService: ScreenServiceProtocol
    private let accessibilityService: AccessibilityServiceProtocol
    private let previewOverlay: PreviewOverlayWindow
    private let snapLayoutBar: SnapLayoutBarWindow
    private let snapEngine: WindowSnappingProtocol
    private let pairingManager: PairedResizeManager

    public init(
        screenService: ScreenServiceProtocol = ScreenService.shared,
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared,
        snapEngine: WindowSnappingProtocol = SnapEngine.shared,
        pairingManager: PairedResizeManager = PairedResizeManager.shared
    ) {
        self.screenService = screenService
        self.accessibilityService = accessibilityService
        self.snapEngine = snapEngine
        self.pairingManager = pairingManager
        self.previewOverlay = PreviewOverlayWindow()
        self.snapLayoutBar = SnapLayoutBarWindow()
    }

    public func startMonitoring() {
        guard eventTap == nil else { return }
        resetDragInteraction()
        monitoringGeneration &+= 1
        let context = EventTapContext(monitor: self, generation: monitoringGeneration)
        eventTapContext = context
        let mask = (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let context = Unmanaged<EventTapContext>.fromOpaque(userInfo).takeUnretainedValue()
            let point = event.location
            let generation = context.generation
            // Snapshot event-time coordinates; do not retain CGEvent across the actor hop.
            Task { @MainActor [weak monitor = context.monitor] in
                monitor?.handleCapturedEvent(type: type, atAXPoint: point, generation: generation)
            }
            return Unmanaged.passUnretained(event)
        }
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask), callback: callback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        )
        guard let tap = eventTap else {
            eventTapContext = nil
            print("[GlobalEventMonitor] Unable to create CGEventTap. Verify Accessibility permissions.")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            eventTap = nil
            eventTapContext = nil
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[GlobalEventMonitor] Drag monitoring active.")
    }

    public func stopMonitoring() {
        // Queued callbacks from the previous registration must not restart a stopped gesture.
        monitoringGeneration &+= 1
        resetDragInteraction()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
        eventTapContext = nil
    }

    private func handleCapturedEvent(type: CGEventType, atAXPoint point: CGPoint, generation: UInt64) {
        guard generation == monitoringGeneration, eventTap != nil else { return }
        let cocoaPoint = ScreenGeometry.axPointToCocoa(
            axPoint: point, primaryScreenHeight: screenService.primaryScreenHeight
        )
        handleEvent(type: type, atCocoaPoint: cocoaPoint)
    }

    /// Internal event seam: tests use the same gesture and placement path as native capture.
    func handleEvent(type: CGEventType, atCocoaPoint point: CGPoint) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetDragInteraction(ignoringUntilRelease: recognition.window != nil || recognition.isIgnored)
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        // A release must terminate ignored gestures even while paused or using the divider.
        if type == .leftMouseUp {
            if !isMasterEnabled || pairingManager.isDraggingDivider {
                resetDragInteraction()
            } else {
                handleRelease(at: point)
            }
            return
        }
        guard type == .leftMouseDragged else { return }
        guard isMasterEnabled, !pairingManager.isDraggingDivider else {
            resetDragInteraction(ignoringUntilRelease: true)
            return
        }
        handleDrag(at: point)
    }

    private func handleDrag(at point: CGPoint) {
        guard let screen = screenService.screenContaining(point: point) else {
            resetDragInteraction(ignoringUntilRelease: true)
            return
        }
        let began = recognition.drag(at: point, visibleFrame: screen.visibleFrame) {
            resolveCandidate(at: point)
        }
        if began {
            snapEngine.cancelPendingOperations()
            if let window = recognition.window { pairingManager.unpairWindow(window) }
        }
        guard recognition.isDragging, let window = recognition.window else { return }
        // When dragging a window, immediately present the collapsed Apple Glass pill
        // at the top of the monitor where the cursor currently is, tracking display switches
        if isTopSnapBarEnabled {
            if snapLayoutBar.presentationState == .hidden {
                snapLayoutBar.presentPill(on: screen)
            } else if snapLayoutBar.currentScreen != screen {
                // User moved the window to another display: migrate pill to the new screen's top
                snapLayoutBar.presentPill(on: screen)
            }
        }

        // Only evaluate hover on SnapLayoutBar and screen edges when the user is actively
        // dragging a window or tab past the intentional movement threshold.

        let visibleFrame = screen.visibleFrame
        let edgeThreshold: CGFloat = 20.0
        let cornerThreshold: CGFloat = 80.0
        let isPortrait = screen.isPortrait

        let isLeft = point.x <= visibleFrame.minX + edgeThreshold
        let isRight = point.x >= visibleFrame.maxX - edgeThreshold
        let isTop = point.y >= visibleFrame.maxY - edgeThreshold
        let isBottom = point.y <= visibleFrame.minY + edgeThreshold

        let isNearTop = point.y >= visibleFrame.maxY - cornerThreshold
        let isNearBottom = point.y <= visibleFrame.minY + cornerThreshold

        var detectedZone: SnapZone?
        var isFromLayoutBar = false

        // 1. Interaction with SnapLayoutBar (Pill or Expanded)
        if isTopSnapBarEnabled {
            if snapLayoutBar.presentationState == .pill {
                // Expand fluidly when cursor approaches the pill
                _ = snapLayoutBar.checkHover(at: point)
            } else if snapLayoutBar.presentationState == .expanded {
                let flyoutHitArea = snapLayoutBar.frame.insetBy(dx: -25, dy: -25)
                if flyoutHitArea.contains(point) {
                    // Cursor hovering over layout cards: select matching slot
                    detectedZone = snapLayoutBar.checkHover(at: point)
                    if detectedZone != nil {
                        isFromLayoutBar = true
                    }
                } else {
                    // Cursor moved away from expanded flyout: collapse smoothly back to pill
                    snapLayoutBar.collapseToPill()
                }
            }
        }

        // 2. Screen edge snapping when no layout bar slot is hovered
        if detectedZone == nil && isEdgeSnapEnabled {
            if isPortrait {
                if isBottom {
                    // Standard bottom edge: 50/50 bottom half
                    detectedZone = .bottomHalf
                } else if isLeft || isRight {
                    // Side edges suggest thirds (1/3) based on cursor height
                    let relativeY = point.y - visibleFrame.minY
                    let thirdHeight = visibleFrame.height / 3.0

                    if relativeY >= (thirdHeight * 2.0) {
                        detectedZone = .topThird
                    } else if relativeY >= thirdHeight {
                        detectedZone = .middleThird
                    } else {
                        detectedZone = .bottomThird
                    }
                } else if isTop && snapLayoutBar.presentationState != .expanded {
                    detectedZone = .topHalf
                }
            } else {
                // Corner quadrants on horizontal display
                if isLeft && isNearTop {
                    detectedZone = .topLeftQuarter
                } else if isRight && isNearTop {
                    detectedZone = .topRightQuarter
                } else if isLeft && isNearBottom {
                    detectedZone = .bottomLeftQuarter
                } else if isRight && isNearBottom {
                    detectedZone = .bottomRightQuarter
                // Halves and maximize
                } else if isTop && snapLayoutBar.presentationState != .expanded {
                    detectedZone = .maximize
                } else if isLeft {
                    detectedZone = .leftHalf
                } else if isRight {
                    detectedZone = .rightHalf
                } else if isBottom {
                    detectedZone = .bottomHalf
                }
            }
        }

        if let zone = detectedZone {
            self.activeZone = zone
            self.activeScreen = screen
            self.isZoneFromLayoutBar = isFromLayoutBar

            let targetRect = snapEngine.previewRect(
                for: window, to: zone, on: screen, forceExactSize: isFromLayoutBar
            )

            self.previewOverlay.present(at: targetRect, animated: true)
        } else {
            clearSnapSelection()
        }
    }

    private func resolveCandidate(at point: CGPoint) -> DragRecognition<WindowElement>.Candidate? {
        let primaryHeight = screenService.primaryScreenHeight
        guard primaryHeight > 0 else { return nil }
        let axPoint = ScreenGeometry.cocoaPointToAX(cocoaPoint: point, primaryScreenHeight: primaryHeight)
        var window = accessibilityService.getWindowUnderPoint(axPoint)
        var frame: CGRect?
        if window == nil,
           let focused = accessibilityService.getFocusedWindow(),
           let focusedFrame = focused.cocoaFrame(primaryScreenHeight: primaryHeight),
           focusedFrame.contains(point) {
            window = focused
            frame = focusedFrame
        }
        guard let window,
              let frame = frame ?? window.cocoaFrame(primaryScreenHeight: primaryHeight) else { return nil }
        return .init(
            window: window, frame: frame, isDesktop: window.isDesktopWindow,
            isOwnWindow: window.pid == ProcessInfo.processInfo.processIdentifier
        )
    }

    private func handleRelease(at point: CGPoint) {
        // A retained NSScreen is not proof that its display is still connected.
        if let activeScreen,
           !screenService.screens.contains(where: { $0.displayID == activeScreen.displayID }) {
            resetDragInteraction()
            return
        }
        let released = recognition.release()
        let zone = activeZone
        let screen = activeScreen ?? screenService.screenContaining(point: point)
        let exact = isZoneFromLayoutBar
        clearSnapSelection()
        snapLayoutBar.dismiss()
        if released.wasDragging {
            snapEngine.completeDrag(window: released.window, zone: zone, screen: screen, forceExactSize: exact)
        }
    }

    private func clearSnapSelection() {
        activeZone = nil
        activeScreen = nil
        isZoneFromLayoutBar = false
        previewOverlay.dismiss()
    }

    private func resetDragInteraction(ignoringUntilRelease: Bool = false) {
        recognition.reset(ignoringUntilRelease: ignoringUntilRelease)
        clearSnapSelection()
        snapLayoutBar.dismiss(animated: false)
        snapEngine.cancelPendingOperations()
    }
}

/// Owned by the monitor for exactly the lifetime of a tap registration.
/// The callback borrows this immutable registration and captures only its values into the task.
private final class EventTapContext {
    weak var monitor: GlobalEventMonitor?
    let generation: UInt64

    init(monitor: GlobalEventMonitor, generation: UInt64) {
        self.monitor = monitor
        self.generation = generation
    }
}
