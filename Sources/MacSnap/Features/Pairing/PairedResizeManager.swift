import Cocoa

/// Gerencia janelas emparelhadas lado a lado e o divisor interativo central.
@MainActor
public final class PairedResizeManager {
    public static let shared = PairedResizeManager()

    private var activePair: PairedSplit?
    private let dividerWindow = DividerHandleWindow()
    private let screenService: ScreenServiceProtocol

    public init(screenService: ScreenServiceProtocol = ScreenService.shared) {
        self.screenService = screenService
        setupDividerCallbacks()
    }

    private func setupDividerCallbacks() {
        dividerWindow.onDividerDragged = { [weak self] currentMouseX in
            guard let self = self, let pair = self.activePair else { return }
            let primaryHeight = self.screenService.primaryScreenHeight
            pair.updateRatioFromDividerX(currentMouseX, primaryScreenHeight: primaryHeight)
            self.dividerWindow.updatePosition(dividerX: pair.dividerX, visibleFrame: pair.visibleFrame)
        }

        dividerWindow.onDividerReleased = {
            // Arraste finalizado; o estado das duas janelas foi atualizado
        }
    }

    /// Registra uma nova janela que acabou de sofrer snap e tenta emparelhar com outra já posicionada.
    public func registerSnap(window: WindowElement, zone: SnapZone, screen: NSScreen) {
        let visibleFrame = screen.visibleFrame

        switch zone {
        case .leftHalf:
            if let existingRight = activePair?.rightWindow {
                // Já existia uma na direita, atualiza o par
                let newPair = PairedSplit(
                    leftWindow: window,
                    rightWindow: existingRight,
                    visibleFrame: visibleFrame,
                    ratio: activePair?.ratio ?? 0.5
                )
                self.activePair = newPair
                showDivider(for: newPair)
            } else {
                // Salva temporariamente como par parcial (aguardando a da direita)
                // Se houver uma janela na direita sob o ponto médio, poderíamos detectá-la
            }

        case .rightHalf:
            if let existingLeft = activePair?.leftWindow {
                let newPair = PairedSplit(
                    leftWindow: existingLeft,
                    rightWindow: window,
                    visibleFrame: visibleFrame,
                    ratio: activePair?.ratio ?? 0.5
                )
                self.activePair = newPair
                showDivider(for: newPair)
            }

        default:
            // Qualquer outro snap (maximizar, cantos) desfaz o emparelhamento lateral
            clearPairing()
        }
    }

    /// Força o emparelhamento explícito de duas janelas conhecidas.
    public func pair(left: WindowElement, right: WindowElement, on screen: NSScreen, ratio: CGFloat = 0.5) {
        let pair = PairedSplit(
            leftWindow: left,
            rightWindow: right,
            visibleFrame: screen.visibleFrame,
            ratio: ratio
        )
        self.activePair = pair
        let primaryHeight = screenService.primaryScreenHeight
        pair.applyCurrentSplit(primaryScreenHeight: primaryHeight)
        showDivider(for: pair)
    }

    private func showDivider(for pair: PairedSplit) {
        dividerWindow.updatePosition(dividerX: pair.dividerX, visibleFrame: pair.visibleFrame)
    }

    /// Remove a barra divisória e desfaz o vínculo de emparelhamento ativo.
    public func clearPairing() {
        activePair = nil
        dividerWindow.orderOut(nil)
    }
}
