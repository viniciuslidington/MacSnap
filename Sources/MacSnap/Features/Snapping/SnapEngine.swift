import Cocoa

/// Owns snap intent from preview through placement and observed pair registration.
@MainActor
public final class SnapEngine: WindowSnappingProtocol {
    public static let shared = SnapEngine()

    private let accessibilityService: AccessibilityServiceProtocol
    private let screenService: ScreenServiceProtocol
    private let pairingManager: PairedResizeManager
    private let discovery: any WindowDiscovering
    private let scheduler: any ActionScheduling
    private var pending: [UUID: any ScheduledAction] = [:]

    public init(
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared,
        screenService: ScreenServiceProtocol = ScreenService.shared,
        pairingManager: PairedResizeManager = PairedResizeManager.shared,
        discovery: (any WindowDiscovering)? = nil,
        scheduler: (any ActionScheduling)? = nil
    ) {
        self.accessibilityService = accessibilityService
        self.screenService = screenService
        self.pairingManager = pairingManager
        self.discovery = discovery ?? NativeWindowDiscovery(accessibilityService: accessibilityService)
        // Resolve the actor-isolated default here to support Swift 6.1 (#81370).
        self.scheduler = scheduler ?? MainActorScheduler.shared
    }

    public func snapFocusedWindow(to zone: SnapZone) {
        guard let window = accessibilityService.getFocusedWindow() else { return }
        let screen = window.cocoaFrame(primaryScreenHeight: screenService.primaryScreenHeight)
            .flatMap { screenService.screenContaining(rect: $0) } ?? screenService.primaryScreen
        guard let screen else { return }
        snapWindow(window, to: zone, on: screen)
    }

    public func previewRect(for window: WindowElement, to zone: SnapZone, on screen: NSScreen, forceExactSize: Bool) -> CGRect {
        SnapTargetResolver.targetRect(
            for: zone, window: window, visibleFrame: screen.visibleFrame,
            primaryScreenHeight: screenService.primaryScreenHeight,
            intent: forceExactSize ? .exactSlot : .adaptive, discovery: discovery
        )
    }

    public func snapWindow(_ window: WindowElement, to zone: SnapZone, on screen: NSScreen, forceExactSize: Bool = false) {
        cancelPendingOperations()
        guard let connected = screenService.screens.first(where: { $0.displayID == screen.displayID }) else { return }
        let target = previewRect(for: window, to: zone, on: connected, forceExactSize: forceExactSize)
        guard window.setCocoaFrame(target, primaryScreenHeight: screenService.primaryScreenHeight) else { return }
        // Registration observes actual geometry, never recalculates an adaptive target or resizes a neighbor.
        pairingManager.registerSnap(window: window, zone: zone, screen: connected)
    }

    public func completeDrag(window: WindowElement?, zone: SnapZone?, screen: NSScreen?, forceExactSize: Bool) {
        cancelPendingOperations()
        guard let screen else { return }
        if let window, let zone {
            schedule(after: 0.03) { [weak self] in
                guard let self else { return }
                self.snapWindow(window, to: zone, on: screen, forceExactSize: forceExactSize)
                self.scheduleRefresh(on: screen)
            }
        } else {
            scheduleRefresh(on: screen)
        }
    }

    public func cancelPendingOperations() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }

    private func scheduleRefresh(on screen: NSScreen) {
        schedule(after: 0.08) { [weak self] in
            guard let self, let connected = self.screenService.screens.first(where: { $0.displayID == screen.displayID }) else { return }
            self.pairingManager.autoDetectAdjacentWindows(on: connected)
        }
    }

    private func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        let id = UUID()
        pending[id] = scheduler.schedule(after: delay) { [weak self] in
            guard let self, self.pending.removeValue(forKey: id) != nil else { return }
            action()
        }
    }
}
