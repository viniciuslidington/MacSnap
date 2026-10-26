import Cocoa
import CoreGraphics

/// Monitors global mouse cursor events using `CGEventTap` to detect
/// when the user drags a window to screen edges or uses the Snap Layout Bar.
/// Includes intelligent multi-monitor cursor following for vertical and horizontal displays.
@MainActor
public final class GlobalEventMonitor: EventMonitoringProtocol {
    public static let shared = GlobalEventMonitor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeZone: SnapZone?
    private var activeScreen: NSScreen?
    private var currentDraggedWindow: WindowElement?
    private var dragStartPoint: CGPoint?
    private var isHoldingWindowOrTab: Bool = false
    private var isDragGestureIgnored: Bool = false
    private var isZoneFromLayoutBar: Bool = false

    private let screenService: ScreenServiceProtocol
    private let accessibilityService: AccessibilityServiceProtocol
    private let previewOverlay: PreviewOverlayWindow
    private let snapLayoutBar: SnapLayoutBarWindow
    private let snapEngine: WindowSnappingProtocol

    public init(
        screenService: ScreenServiceProtocol = ScreenService.shared,
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared,
        snapEngine: WindowSnappingProtocol = SnapEngine.shared
    ) {
        self.screenService = screenService
        self.accessibilityService = accessibilityService
        self.snapEngine = snapEngine
        self.previewOverlay = PreviewOverlayWindow()
        self.snapLayoutBar = SnapLayoutBarWindow()
    }

    public func startMonitoring() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo = userInfo else {
                return Unmanaged.passRetained(event)
            }
            let monitor = Unmanaged<GlobalEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in
                monitor.handleEvent(type: type, event: event)
            }
            return Unmanaged.passRetained(event)
        }

        let observer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: observer
        )

        guard let tap = eventTap else {
            print("[GlobalEventMonitor] Warning: Unable to create CGEventTap. Please verify Accessibility permissions.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[GlobalEventMonitor] Drag monitoring active.")
    }

    public func stopMonitoring() {
        self.previewOverlay.dismiss()
        self.snapLayoutBar.dismiss(animated: false)
        self.activeZone = nil
        self.activeScreen = nil
        self.isZoneFromLayoutBar = false
        self.currentDraggedWindow = nil
        self.dragStartPoint = nil
        self.isHoldingWindowOrTab = false
        self.isDragGestureIgnored = false

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let mouseLocation = NSEvent.mouseLocation

        // If user is currently dragging an interactive resize divider, completely suppress
        // the top Snap Bar modal and snap previews so they never get in the way.
        if PairedResizeManager.shared.isDraggingDivider {
            if snapLayoutBar.presentationState != .hidden {
                snapLayoutBar.dismiss(animated: false)
            }
            if previewOverlay.isVisible {
                previewOverlay.dismiss()
            }
            self.activeZone = nil
            self.currentDraggedWindow = nil
            self.dragStartPoint = nil
            self.isHoldingWindowOrTab = false
            self.isDragGestureIgnored = false
            return
        }

        switch type {
        case .leftMouseDragged:
            handleDrag(at: mouseLocation)
        case .leftMouseUp:
            handleRelease()
        default:
            break
        }
    }

    private func handleDrag(at point: CGPoint) {
        // If this drag sequence was already determined to start in an invalid zone
        // (e.g. In-app editor body, desktop wallpaper, menu bar, or dock), ignore all remaining drag events until mouseUp
        if isDragGestureIgnored {
            return
        }

        guard let screen = screenService.screenContaining(point: point) else { return }

        // Capture and validate the dragged window at the exact start of movement
        if currentDraggedWindow == nil {
            // Layer 1: Exclude Menu Bar and Dock.
            // In Cocoa coordinates, point.y >= screen.visibleFrame.maxY - 1.0 is in the Menu Bar,
            // and !screen.visibleFrame.contains(point) covers Dock or off-screen coordinates.
            let visibleFrame = screen.visibleFrame
            if !visibleFrame.contains(point) || point.y >= (visibleFrame.maxY - 1.0) {
                isDragGestureIgnored = true
                return
            }

            guard let primaryScreen = screenService.primaryScreen ?? NSScreen.screens.first else {
                isDragGestureIgnored = true
                return
            }
            let primaryHeight = primaryScreen.frame.height

            // Layer 2: Hit-test the actual element under the cursor position.
            // This prevents attributing clicks on empty desktop to the last focused application.
            let axPoint = ScreenGeometry.cocoaPointToAX(cocoaPoint: point, primaryScreenHeight: primaryHeight)
            var candidateWindow = accessibilityService.getWindowUnderPoint(axPoint)

            // Fallback: If getWindowUnderPoint didn't resolve (e.g. non-standard custom element),
            // allow focused window ONLY IF the cursor is physically inside the focused window's frame.
            if candidateWindow == nil,
               let focused = accessibilityService.getFocusedWindow(),
               let focusedFrame = focused.cocoaFrame(primaryScreenHeight: primaryHeight),
               focusedFrame.contains(point) {
                candidateWindow = focused
            }

            guard let targetWindow = candidateWindow else {
                isDragGestureIgnored = true
                return
            }

            // Layer 3: Exclude Desktop wallpaper (AXDesktopWindow) and MacSnap's own interface windows.
            if targetWindow.isDesktopWindow || targetWindow.pid == ProcessInfo.processInfo.processIdentifier {
                isDragGestureIgnored = true
                return
            }

            // Layer 4: Validate that the click started strictly in the upper header / tab bar region.
            // Grabbing or selecting in the window body (editor text, buttons, web content) must NEVER trigger snapping.
            guard targetWindow.isPointInHeaderRegion(point, primaryScreenHeight: primaryHeight) else {
                isDragGestureIgnored = true
                return
            }

            currentDraggedWindow = targetWindow
            dragStartPoint = point
        }

        // Layer 5: Intentional drag threshold.
        // Requires a deliberate 14pt movement before activating the Snap Layout Bar or snap zones,
        // preventing micro-jitter from simple clicks on tabs or window controls.
        let dragDist = hypot(point.x - (dragStartPoint?.x ?? point.x), point.y - (dragStartPoint?.y ?? point.y))
        let dragThreshold: CGFloat = 14.0
        if !isHoldingWindowOrTab && dragDist >= dragThreshold && currentDraggedWindow != nil {
            isHoldingWindowOrTab = true
            if let window = currentDraggedWindow {
                PairedResizeManager.shared.unpairWindow(window)
            }
        }

        // When dragging a window, immediately present the collapsed Apple Glass pill
        // at the top of the monitor where the cursor currently is, tracking display switches
        if isHoldingWindowOrTab {
            if snapLayoutBar.presentationState == .hidden {
                snapLayoutBar.presentPill(on: screen)
            } else if snapLayoutBar.currentScreen != screen {
                // User moved the window to another display: migrate pill to the new screen's top
                snapLayoutBar.presentPill(on: screen)
            }
        }

        // Only evaluate hover on SnapLayoutBar and screen edges when the user is actively
        // dragging a window or tab past the intentional movement threshold.
        guard isHoldingWindowOrTab else { return }

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

        // 2. Screen edge snapping when no layout bar slot is hovered
        if detectedZone == nil {
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

            // Intelligent dynamic preview:
            // When choosing from the layout bar modal, strictly display the exact card slot geometry ("tamanho certo").
            // For edge snapping, calculate flush boundary if a genuine partner exists.
            let targetRect: CGRect
            if !isFromLayoutBar, let flush = PairedResizeManager.shared.calculateFlushTargetRect(for: zone, screen: screen, windowToExclude: currentDraggedWindow) {
                targetRect = flush.targetRect
            } else {
                targetRect = zone.targetRect(for: visibleFrame)
            }

            self.previewOverlay.present(at: targetRect, animated: true)
        } else {
            if self.activeZone != nil {
                self.activeZone = nil
                self.activeScreen = nil
                self.isZoneFromLayoutBar = false
                self.previewOverlay.dismiss()
            }
        }
    }

    private func handleRelease() {
        self.previewOverlay.dismiss()
        self.snapLayoutBar.dismiss()

        if self.isHoldingWindowOrTab, let zone = self.activeZone, let window = self.currentDraggedWindow {
            let targetScreen = self.activeScreen ?? self.screenService.screenContaining(point: NSEvent.mouseLocation)

            if let screen = targetScreen {
                let fromModal = self.isZoneFromLayoutBar
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    self?.snapEngine.snapWindow(window, to: zone, on: screen, forceExactSize: fromModal)
                    // Settlement pass: verify and ensure pairing for any adjacent windows (including same application)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        PairedResizeManager.shared.autoDetectAdjacentWindows(on: screen)
                    }
                }
            }
        } else if self.isHoldingWindowOrTab {
            // Window was dragged and dropped: check if it was placed adjacent to an existing window (including same app)
            let currentScreen = self.screenService.screenContaining(point: NSEvent.mouseLocation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                PairedResizeManager.shared.autoDetectAdjacentWindows(on: currentScreen)
            }
        }

        self.activeZone = nil
        self.activeScreen = nil
        self.isZoneFromLayoutBar = false
        self.currentDraggedWindow = nil
        self.dragStartPoint = nil
        self.isHoldingWindowOrTab = false
        self.isDragGestureIgnored = false
    }
}
