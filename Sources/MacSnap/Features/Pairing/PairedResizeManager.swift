import Cocoa

/// Gerencia janelas emparelhadas lado a lado (horizontal) ou empilhadas (vertical) e o divisor interativo central.
@MainActor
public final class PairedResizeManager {
    public static let shared = PairedResizeManager()

    private var activePair: PairedSplit?
    private let dividerWindow = DividerHandleWindow()
    private let screenService: ScreenServiceProtocol

    // Histórico recente para permitir emparelhamento dinâmico
    private weak var recentLeftWindow: WindowElement?
    private weak var recentRightWindow: WindowElement?
    private weak var recentTopWindow: WindowElement?
    private weak var recentBottomWindow: WindowElement?

    public init(screenService: ScreenServiceProtocol = ScreenService.shared) {
        self.screenService = screenService
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

    /// Registra uma nova janela que sofreu snap e ativa o divisor caso haja uma parceira oposta.
    public func registerSnap(window: WindowElement, zone: SnapZone, screen: NSScreen) {
        let visibleFrame = screen.visibleFrame

        switch zone {
        // 1. Emparelhamento Horizontal Simétrico (50/50)
        case .leftHalf:
            recentLeftWindow = window
            if let right = recentRightWindow {
                createHorizontalPair(left: window, right: right, ratio: 0.5, visibleFrame: visibleFrame)
            }

        case .rightHalf:
            recentRightWindow = window
            if let left = recentLeftWindow {
                createHorizontalPair(left: left, right: window, ratio: 0.5, visibleFrame: visibleFrame)
            }

        // 2. Emparelhamento Horizontal Assimétrico (2/3 e 1/3)
        case .leftTwoThirds:
            recentLeftWindow = window
            if let right = recentRightWindow {
                createHorizontalPair(left: window, right: right, ratio: 2.0 / 3.0, visibleFrame: visibleFrame)
            }

        case .rightOneThird:
            recentRightWindow = window
            if let left = recentLeftWindow {
                createHorizontalPair(left: left, right: window, ratio: 2.0 / 3.0, visibleFrame: visibleFrame)
            }

        // 3. Emparelhamento Horizontal Assimétrico Invertido (1/3 e 2/3)
        case .leftOneThird, .leftThird:
            recentLeftWindow = window
            if let right = recentRightWindow {
                createHorizontalPair(left: window, right: right, ratio: 1.0 / 3.0, visibleFrame: visibleFrame)
            }

        case .rightTwoThirds:
            recentRightWindow = window
            if let left = recentLeftWindow {
                createHorizontalPair(left: left, right: window, ratio: 1.0 / 3.0, visibleFrame: visibleFrame)
            }

        // 4. Emparelhamento Vertical Simétrico (Topo e Base 50/50)
        case .topHalf:
            recentTopWindow = window
            if let bottom = recentBottomWindow {
                createVerticalPair(top: window, bottom: bottom, ratio: 0.5, visibleFrame: visibleFrame)
            }

        case .bottomHalf:
            recentBottomWindow = window
            if let top = recentTopWindow {
                createVerticalPair(top: top, bottom: window, ratio: 0.5, visibleFrame: visibleFrame)
            }

        // 5. Emparelhamento Vertical Assimétrico (2/3 e 1/3)
        case .topTwoThirds:
            recentTopWindow = window
            if let bottom = recentBottomWindow {
                createVerticalPair(top: window, bottom: bottom, ratio: 2.0 / 3.0, visibleFrame: visibleFrame)
            }

        // 6. Emparelhamento Vertical Assimétrico Invertido (1/3 e 2/3)
        case .bottomTwoThirds:
            recentBottomWindow = window
            if let top = recentTopWindow {
                createVerticalPair(top: top, bottom: window, ratio: 1.0 / 3.0, visibleFrame: visibleFrame)
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
