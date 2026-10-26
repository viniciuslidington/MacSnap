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
        // 1. Emparelhamento Horizontal (Lado a Lado)
        case .leftHalf:
            recentLeftWindow = window
            if let right = recentRightWindow {
                let pair = PairedSplit(
                    firstWindow: window,
                    secondWindow: right,
                    orientation: .horizontal,
                    visibleFrame: visibleFrame,
                    ratio: activePair?.ratio ?? 0.5
                )
                self.activePair = pair
                showDivider(for: pair)
            }

        case .rightHalf:
            recentRightWindow = window
            if let left = recentLeftWindow {
                let pair = PairedSplit(
                    firstWindow: left,
                    secondWindow: window,
                    orientation: .horizontal,
                    visibleFrame: visibleFrame,
                    ratio: activePair?.ratio ?? 0.5
                )
                self.activePair = pair
                showDivider(for: pair)
            }

        // 2. Emparelhamento Vertical (Topo e Base - Ideal para Monitor Vertical)
        case .topHalf:
            recentTopWindow = window
            if let bottom = recentBottomWindow {
                let pair = PairedSplit(
                    firstWindow: window,
                    secondWindow: bottom,
                    orientation: .vertical,
                    visibleFrame: visibleFrame,
                    ratio: activePair?.ratio ?? 0.5
                )
                self.activePair = pair
                showDivider(for: pair)
            }

        case .bottomHalf:
            recentBottomWindow = window
            if let top = recentTopWindow {
                let pair = PairedSplit(
                    firstWindow: top,
                    secondWindow: window,
                    orientation: .vertical,
                    visibleFrame: visibleFrame,
                    ratio: activePair?.ratio ?? 0.5
                )
                self.activePair = pair
                showDivider(for: pair)
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
