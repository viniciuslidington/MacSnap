import Cocoa

/// Gerencia janelas emparelhadas lado a lado (horizontal) ou empilhadas (vertical) e o divisor interativo central.
/// Possui auto-descoberta dinâmica de janelas vizinhas na intercessão da tela.
@MainActor
public final class PairedResizeManager {
    public static let shared = PairedResizeManager()

    private var activePair: PairedSplit?
    private let dividerWindow = DividerHandleWindow()
    private let screenService: ScreenServiceProtocol
    private let accessibilityService: AccessibilityServiceProtocol

    // Histórico recente para permitir emparelhamento dinâmico
    private weak var recentLeftWindow: WindowElement?
    private weak var recentRightWindow: WindowElement?
    private weak var recentTopWindow: WindowElement?
    private weak var recentBottomWindow: WindowElement?

    public init(
        screenService: ScreenServiceProtocol = ScreenService.shared,
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared
    ) {
        self.screenService = screenService
        self.accessibilityService = accessibilityService
        setupDividerCallbacks()
    }

    private func setupDividerCallbacks() {
        dividerWindow.onDividerDragged = { [weak self] cursorCoordinate in
            guard let self = self, let pair = self.activePair else { return }
            let primaryHeight = self.screenService.primaryScreenHeight
            pair.updateRatioFromCursor(cursorCoordinate: cursorCoordinate, primaryScreenHeight: primaryHeight)
            self.dividerWindow.update(for: pair)
        }

        dividerWindow.onDividerReleased = {
            // Arraste finalizado; proporção salva
        }
    }

    /// Busca ativamente se já existe uma janela aberta no lado oposto para conectar o par imediatamente.
    private func findAdjacentWindow(atCocoaPoint point: CGPoint, excludingPid: pid_t) -> WindowElement? {
        let primaryHeight = screenService.primaryScreenHeight
        let axPoint = ScreenGeometry.cocoaPointToAX(cocoaPoint: point, primaryScreenHeight: primaryHeight)
        let myPid = ProcessInfo.processInfo.processIdentifier

        if let candidate = accessibilityService.getWindowUnderPoint(axPoint),
           candidate.pid != excludingPid && candidate.pid != myPid {
            return candidate
        }
        return nil
    }

    /// Registra uma nova janela que sofreu snap e ativa o divisor caso haja uma parceira oposta.
    public func registerSnap(window: WindowElement, zone: SnapZone, screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let w = visibleFrame.width
        let h = visibleFrame.height
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y

        switch zone {
        // 1. Emparelhamento Horizontal Simétrico (50/50)
        case .leftHalf:
            recentLeftWindow = window
            let right = recentRightWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.75), y: y + (h * 0.5)),
                excludingPid: window.pid
            )
            if let partner = right {
                recentRightWindow = partner
                createHorizontalPair(left: window, right: partner, ratio: 0.5, visibleFrame: visibleFrame)
            }

        case .rightHalf:
            recentRightWindow = window
            let left = recentLeftWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.25), y: y + (h * 0.5)),
                excludingPid: window.pid
            )
            if let partner = left {
                recentLeftWindow = partner
                createHorizontalPair(left: partner, right: window, ratio: 0.5, visibleFrame: visibleFrame)
            }

        // 2. Emparelhamento Horizontal Assimétrico (2/3 e 1/3)
        case .leftTwoThirds:
            recentLeftWindow = window
            let right = recentRightWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.85), y: y + (h * 0.5)),
                excludingPid: window.pid
            )
            if let partner = right {
                recentRightWindow = partner
                createHorizontalPair(left: window, right: partner, ratio: 2.0 / 3.0, visibleFrame: visibleFrame)
            }

        case .rightOneThird:
            recentRightWindow = window
            let left = recentLeftWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.35), y: y + (h * 0.5)),
                excludingPid: window.pid
            )
            if let partner = left {
                recentLeftWindow = partner
                createHorizontalPair(left: partner, right: window, ratio: 2.0 / 3.0, visibleFrame: visibleFrame)
            }

        // 3. Emparelhamento Horizontal Assimétrico Invertido (1/3 e 2/3)
        case .leftOneThird, .leftThird:
            recentLeftWindow = window
            let right = recentRightWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.65), y: y + (h * 0.5)),
                excludingPid: window.pid
            )
            if let partner = right {
                recentRightWindow = partner
                createHorizontalPair(left: window, right: partner, ratio: 1.0 / 3.0, visibleFrame: visibleFrame)
            }

        case .rightTwoThirds:
            recentRightWindow = window
            let left = recentLeftWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.15), y: y + (h * 0.5)),
                excludingPid: window.pid
            )
            if let partner = left {
                recentLeftWindow = partner
                createHorizontalPair(left: partner, right: window, ratio: 1.0 / 3.0, visibleFrame: visibleFrame)
            }

        // 4. Emparelhamento Vertical Simétrico (Topo e Base 50/50)
        case .topHalf:
            recentTopWindow = window
            let bottom = recentBottomWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.5), y: y + (h * 0.25)),
                excludingPid: window.pid
            )
            if let partner = bottom {
                recentBottomWindow = partner
                createVerticalPair(top: window, bottom: partner, ratio: 0.5, visibleFrame: visibleFrame)
            }

        case .bottomHalf:
            recentBottomWindow = window
            let top = recentTopWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.5), y: y + (h * 0.75)),
                excludingPid: window.pid
            )
            if let partner = top {
                recentTopWindow = partner
                createVerticalPair(top: partner, bottom: window, ratio: 0.5, visibleFrame: visibleFrame)
            }

        // 5. Emparelhamento Vertical Assimétrico (2/3 e 1/3)
        case .topTwoThirds:
            recentTopWindow = window
            let bottom = recentBottomWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.5), y: y + (h * 0.15)),
                excludingPid: window.pid
            )
            if let partner = bottom {
                recentBottomWindow = partner
                createVerticalPair(top: window, bottom: partner, ratio: 2.0 / 3.0, visibleFrame: visibleFrame)
            }

        // 6. Emparelhamento Vertical Assimétrico Invertido (1/3 e 2/3)
        case .bottomTwoThirds:
            recentBottomWindow = window
            let top = recentTopWindow ?? findAdjacentWindow(
                atCocoaPoint: CGPoint(x: x + (w * 0.5), y: y + (h * 0.85)),
                excludingPid: window.pid
            )
            if let partner = top {
                recentTopWindow = partner
                createVerticalPair(top: partner, bottom: window, ratio: 1.0 / 3.0, visibleFrame: visibleFrame)
            }

        case .maximize:
            clearPairing()
            recentLeftWindow = nil
            recentRightWindow = nil
            recentTopWindow = nil
            recentBottomWindow = nil

        default:
            clearPairing()
        }
    }

    private func createHorizontalPair(left: WindowElement, right: WindowElement, ratio: CGFloat, visibleFrame: CGRect) {
        guard left.rawElement != right.rawElement else { return }
        let pair = PairedSplit(
            firstWindow: left,
            secondWindow: right,
            orientation: .horizontal,
            visibleFrame: visibleFrame,
            ratio: ratio
        )
        self.activePair = pair
        showDivider(for: pair)
    }

    private func createVerticalPair(top: WindowElement, bottom: WindowElement, ratio: CGFloat, visibleFrame: CGRect) {
        guard top.rawElement != bottom.rawElement else { return }
        let pair = PairedSplit(
            firstWindow: top,
            secondWindow: bottom,
            orientation: .vertical,
            visibleFrame: visibleFrame,
            ratio: ratio
        )
        self.activePair = pair
        showDivider(for: pair)
    }

    /// Força o emparelhamento explícito de duas janelas conhecidas.
    public func pair(
        first: WindowElement,
        second: WindowElement,
        orientation: SplitOrientation,
        on screen: NSScreen,
        ratio: CGFloat = 0.5
    ) {
        let pair = PairedSplit(
            firstWindow: first,
            secondWindow: second,
            orientation: orientation,
            visibleFrame: screen.visibleFrame,
            ratio: ratio
        )
        self.activePair = pair
        let primaryHeight = screenService.primaryScreenHeight
        pair.applyCurrentSplit(primaryScreenHeight: primaryHeight)
        showDivider(for: pair)
    }

    private func showDivider(for pair: PairedSplit) {
        dividerWindow.update(for: pair)
    }

    /// Remove a barra divisória e desfaz o vínculo de emparelhamento ativo.
    public func clearPairing() {
        activePair = nil
        dividerWindow.orderOut(nil)
    }
}
