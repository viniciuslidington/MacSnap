import Cocoa

/// Gerencia janelas emparelhadas lado a lado (horizontal) ou empilhadas (vertical) e o divisor interativo central.
/// Possui auto-descoberta dinâmica de janelas vizinhas na intercessão da tela e cálculo de encaixe sem sobreposição.
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
    public func findAdjacentWindow(atCocoaPoint point: CGPoint, excludingPid: pid_t) -> WindowElement? {
        let primaryHeight = screenService.primaryScreenHeight
        let axPoint = ScreenGeometry.cocoaPointToAX(cocoaPoint: point, primaryScreenHeight: primaryHeight)
        let myPid = ProcessInfo.processInfo.processIdentifier

        if let candidate = accessibilityService.getWindowUnderPoint(axPoint),
           candidate.pid != excludingPid && candidate.pid != myPid {
            return candidate
        }
        return nil
    }

    /// Calcula a área exata restante se já houver uma janela parceira posicionada no lado oposto,
    /// evitando sobreposição mesmo quando a janela parceira tiver tamanho customizado ou altura mínima (ex: Xcode).
    public func calculateFlushTargetRect(
        for zone: SnapZone,
        screen: NSScreen,
        windowToExclude: WindowElement?
    ) -> (targetRect: CGRect, partner: WindowElement, orientation: SplitOrientation, ratio: CGFloat)? {
        let visibleFrame = screen.visibleFrame
        let w = visibleFrame.width
        let h = visibleFrame.height
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let primaryHeight = screenService.primaryScreenHeight
        let excludePid = windowToExclude?.pid ?? 0

        switch zone {
        // Encaixe na parte inferior: busca parceiro no topo
        case .bottomHalf, .bottomThird, .bottomTwoThirds:
            let samplePoint = CGPoint(x: x + (w * 0.5), y: y + (h * 0.75))
            if let topPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingPid: excludePid),
               let topFrame = topPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                // topFrame.minY é a borda inferior real da janela superior
                let availableHeight = topFrame.minY - y
                if availableHeight >= 80 {
                    let flushRect = CGRect(x: x, y: y, width: w, height: availableHeight)
                    let ratio = min(max(topFrame.height / h, 0.15), 0.85)
                    return (flushRect, topPartner, .vertical, ratio)
                }
            }

        // Encaixe na parte superior: busca parceiro na base
        case .topHalf, .topThird, .topTwoThirds:
            let samplePoint = CGPoint(x: x + (w * 0.5), y: y + (h * 0.25))
            if let bottomPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingPid: excludePid),
               let bottomFrame = bottomPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                let bottomTopEdge = bottomFrame.maxY
                let availableHeight = (y + h) - bottomTopEdge
                if availableHeight >= 80 {
                    let flushRect = CGRect(x: x, y: bottomTopEdge, width: w, height: availableHeight)
                    let ratio = min(max(availableHeight / h, 0.15), 0.85)
                    return (flushRect, bottomPartner, .vertical, ratio)
                }
            }

        // Encaixe na direita: busca parceiro na esquerda
        case .rightHalf, .rightOneThird, .rightTwoThirds:
            let samplePoint = CGPoint(x: x + (w * 0.25), y: y + (h * 0.5))
            if let leftPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingPid: excludePid),
               let leftFrame = leftPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                let leftRightEdge = leftFrame.maxX
                let availableWidth = (x + w) - leftRightEdge
                if availableWidth >= 100 {
                    let flushRect = CGRect(x: leftRightEdge, y: y, width: availableWidth, height: h)
                    let ratio = min(max(leftFrame.width / w, 0.15), 0.85)
                    return (flushRect, leftPartner, .horizontal, ratio)
                }
            }

        // Encaixe na esquerda: busca parceiro na direita
        case .leftHalf, .leftOneThird, .leftThird, .leftTwoThirds:
            let samplePoint = CGPoint(x: x + (w * 0.75), y: y + (h * 0.5))
            if let rightPartner = findAdjacentWindow(atCocoaPoint: samplePoint, excludingPid: excludePid),
               let rightFrame = rightPartner.cocoaFrame(primaryScreenHeight: primaryHeight) {
                let rightLeftEdge = rightFrame.minX
                let availableWidth = rightLeftEdge - x
                if availableWidth >= 100 {
                    let flushRect = CGRect(x: x, y: y, width: availableWidth, height: h)
                    let ratio = min(max(availableWidth / w, 0.15), 0.85)
                    return (flushRect, rightPartner, .horizontal, ratio)
                }
            }

        default:
            break
        }

        return nil
    }

    /// Registra uma nova janela que sofreu snap e ativa o divisor caso haja uma parceira oposta.
    public func registerSnap(window: WindowElement, zone: SnapZone, screen: NSScreen) {
        let visibleFrame = screen.visibleFrame

        // 1. Tenta emparelhar dinamicamente usando a parceira detectada na intercessão
        if let flush = calculateFlushTargetRect(for: zone, screen: screen, windowToExclude: window) {
            if flush.orientation == .vertical {
                if zone == .topHalf || zone == .topThird || zone == .topTwoThirds {
                    recentTopWindow = window
                    recentBottomWindow = flush.partner
                    createVerticalPair(top: window, bottom: flush.partner, ratio: flush.ratio, visibleFrame: visibleFrame)
                } else {
                    recentTopWindow = flush.partner
                    recentBottomWindow = window
                    createVerticalPair(top: flush.partner, bottom: window, ratio: flush.ratio, visibleFrame: visibleFrame)
                }
            } else {
                if zone == .leftHalf || zone == .leftOneThird || zone == .leftThird || zone == .leftTwoThirds {
                    recentLeftWindow = window
                    recentRightWindow = flush.partner
                    createHorizontalPair(left: window, right: flush.partner, ratio: flush.ratio, visibleFrame: visibleFrame)
                } else {
                    recentLeftWindow = flush.partner
                    recentRightWindow = window
                    createHorizontalPair(left: flush.partner, right: window, ratio: flush.ratio, visibleFrame: visibleFrame)
                }
            }
            return
        }

        // 2. Fallback de histórico recente caso não tenha detectado na tela
        switch zone {
        case .leftHalf, .leftOneThird, .leftThird, .leftTwoThirds:
            recentLeftWindow = window
            if let right = recentRightWindow {
                createHorizontalPair(left: window, right: right, ratio: 0.5, visibleFrame: visibleFrame)
            }

        case .rightHalf, .rightOneThird, .rightTwoThirds:
            recentRightWindow = window
            if let left = recentLeftWindow {
                createHorizontalPair(left: left, right: window, ratio: 0.5, visibleFrame: visibleFrame)
            }

        case .topHalf, .topThird, .topTwoThirds:
            recentTopWindow = window
            if let bottom = recentBottomWindow {
                createVerticalPair(top: window, bottom: bottom, ratio: 0.5, visibleFrame: visibleFrame)
            }

        case .bottomHalf, .bottomThird, .bottomTwoThirds:
            recentBottomWindow = window
            if let top = recentTopWindow {
                createVerticalPair(top: top, bottom: window, ratio: 0.5, visibleFrame: visibleFrame)
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
