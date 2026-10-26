import Cocoa

/// Orchestrates window snapping rules, calculating screen geometries and
/// registering pairings when applicable.
@MainActor
public final class SnapEngine: WindowSnappingProtocol {
    public static let shared = SnapEngine()

    private let accessibilityService: AccessibilityServiceProtocol
    private let screenService: ScreenServiceProtocol
    private let pairingManager: PairedResizeManager

    public init(
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared,
        screenService: ScreenServiceProtocol = ScreenService.shared,
        pairingManager: PairedResizeManager = PairedResizeManager.shared
    ) {
        self.accessibilityService = accessibilityService
        self.screenService = screenService
        self.pairingManager = pairingManager
    }

    public func snapFocusedWindow(to zone: SnapZone) {
        guard let window = accessibilityService.getFocusedWindow() else {
            print("[SnapEngine] No focused window found.")
            return
        }

        // Determine which screen contains the window
        let primaryHeight = screenService.primaryScreenHeight
        guard let currentCocoaFrame = window.cocoaFrame(primaryScreenHeight: primaryHeight),
              let screen = screenService.screenContaining(rect: currentCocoaFrame) else {
            if let mainScreen = screenService.primaryScreen {
                snapWindow(window, to: zone, on: mainScreen)
            }
            return
        }

        snapWindow(window, to: zone, on: screen)
    }

    public func snapWindow(
        _ window: WindowElement,
        to zone: SnapZone,
        on screen: NSScreen,
        forceExactSize: Bool = false
    ) {
        let visibleFrame = screen.visibleFrame
        let primaryHeight = screenService.primaryScreenHeight

        // Smart flush snapping without overlap: if a paired window already exists (e.g. Xcode at top),
        // calculate the exact remaining space to dock flush like a puzzle piece.
        // When forceExactSize is true (e.g. user selected an explicit slot in the layout bar modal),
        // use the exact target rectangle of the slot without alteration.
        let targetRect: CGRect
        if !forceExactSize, let flush = pairingManager.calculateFlushTargetRect(for: zone, screen: screen, windowToExclude: window) {
            targetRect = flush.targetRect
        } else {
            targetRect = zone.targetRect(for: visibleFrame)
        }

        let success = window.setCocoaFrame(targetRect, primaryScreenHeight: primaryHeight)
        if success {
            pairingManager.registerSnap(window: window, zone: zone, screen: screen)
        }
    }
}
