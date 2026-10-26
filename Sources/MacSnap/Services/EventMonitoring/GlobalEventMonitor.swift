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
        self.currentDraggedWindow = nil
        self.dragStartPoint = nil
        self.isHoldingWindowOrTab = false

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
        guard let screen = screenService.screenContaining(point: point) else { return }

        // Capture the dragged window at the start of movement before focus changes
        if currentDraggedWindow == nil {
            currentDraggedWindow = accessibilityService.getFocusedWindow()
            dragStartPoint = point
        }

        // Determine if user is actively dragging a window/tab
        let dragDist = hypot(point.x - (dragStartPoint?.x ?? point.x), point.y - (dragStartPoint?.y ?? point.y))
        if !isHoldingWindowOrTab && dragDist >= 4.0 && currentDraggedWindow != nil {
            isHoldingWindowOrTab = true
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

        // 1. Interaction with SnapLayoutBar (Pill or Expanded)
        if snapLayoutBar.presentationState == .pill {
            // Expand fluidly when cursor approaches the pill
            _ = snapLayoutBar.checkHover(at: point)
        } else if snapLayoutBar.presentationState == .expanded {
            let flyoutHitArea = snapLayoutBar.frame.insetBy(dx: -25, dy: -25)
            if flyoutHitArea.contains(point) {
                // Cursor hovering over layout cards: select matching slot
                detectedZone = snapLayoutBar.checkHover(at: point)
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

            // Intelligent dynamic preview: if an adjacent paired window exists,
            // flush preview boundary against it to avoid ugly screen overlap
            let targetRect: CGRect
            if let flush = PairedResizeManager.shared.calculateFlushTargetRect(for: zone, screen: screen, windowToExclude: currentDraggedWindow) {
                targetRect = flush.targetRect
            } else {
                targetRect = zone.targetRect(for: visibleFrame)
            }

            self.previewOverlay.present(at: targetRect, animated: true)
        } else {
            if self.activeZone != nil {
                self.activeZone = nil
                self.activeScreen = nil
                self.previewOverlay.dismiss()
            }
        }
    }

    private func handleRelease() {
        self.previewOverlay.dismiss()
        self.snapLayoutBar.dismiss()

        if let zone = self.activeZone {
            let windowToSnap = self.currentDraggedWindow ?? self.accessibilityService.getFocusedWindow()
            let targetScreen = self.activeScreen ?? self.screenService.screenContaining(point: NSEvent.mouseLocation)

            if let window = windowToSnap, let screen = targetScreen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    self?.snapEngine.snapWindow(window, to: zone, on: screen)
                }
            } else if windowToSnap != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    self?.snapEngine.snapFocusedWindow(to: zone)
                }
            }
        }

        self.activeZone = nil
        self.activeScreen = nil
        self.currentDraggedWindow = nil
        self.dragStartPoint = nil
        self.isHoldingWindowOrTab = false
    }
}
