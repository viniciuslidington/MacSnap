import Cocoa

/// Orquestra a aplicação de regras de snap em janelas, calculando tamanhos de tela e
/// registrando emparelhamentos quando aplicável.
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
            print("[SnapEngine] Nenhuma janela em foco encontrada.")
            return
        }

        // Descobre em qual tela a janela está
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

    public func snapWindow(_ window: WindowElement, to zone: SnapZone, on screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let targetRect = zone.targetRect(for: visibleFrame)
        let primaryHeight = screenService.primaryScreenHeight

        let success = window.setCocoaFrame(targetRect, primaryScreenHeight: primaryHeight)
        if success {
            pairingManager.registerSnap(window: window, zone: zone, screen: screen)
        }
    }
}
