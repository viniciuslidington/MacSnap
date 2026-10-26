import Cocoa

/// Estado isolado de emparelhamento por monitor, mantendo histórico e divisor independente.
@MainActor
public final class ScreenPairState {
    public let screenID: CGDirectDisplayID
    public var pair: PairedSplit?
    public let dividerWindow: DividerHandleWindow

    public weak var recentLeftWindow: WindowElement?
    public weak var recentRightWindow: WindowElement?
    public weak var recentTopWindow: WindowElement?
    public weak var recentBottomWindow: WindowElement?

    public init(screenID: CGDirectDisplayID) {
        self.screenID = screenID
        self.dividerWindow = DividerHandleWindow()
    }

    public func clear() {
        pair = nil
        dividerWindow.orderOut(nil)
        recentLeftWindow = nil
        recentRightWindow = nil
        recentTopWindow = nil
        recentBottomWindow = nil
    }
}

/// Gerencia janelas emparelhadas lado a lado (horizontal) ou empilhadas (vertical) e o divisor interativo central.
/// Suporta múltiplos monitores simultâneos mantendo os pares ativos em cada tela de forma independente.
@MainActor
public final class PairedResizeManager {
    public static let shared = PairedResizeManager()

    /// Estados de emparelhamento indexados pelo ID numérico de cada monitor (displayID)
    private var statesByScreen: [CGDirectDisplayID: ScreenPairState] = [:]
    private let screenService: ScreenServiceProtocol
    private let accessibilityService: AccessibilityServiceProtocol

    public init(
        screenService: ScreenServiceProtocol = ScreenService.shared,
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared
    ) {
        self.screenService = screenService
        self.accessibilityService = accessibilityService
    }

    /// Retorna ou inicializa o estado de emparelhamento dedicado para a tela especificada.
    public func state(for screen: NSScreen) -> ScreenPairState {
        let id = screen.displayID
        if let existing = statesByScreen[id] {
            return existing
        }
        let newState = ScreenPairState(screenID: id)
        setupDividerCallbacks(for: newState)
        statesByScreen[id] = newState
        return newState
    }

    private func setupDividerCallbacks(for state: ScreenPairState) {
        state.dividerWindow.onDividerDragged = { [weak self, weak state] cursorCoordinate in
            guard let self = self, let state = state, let pair = state.pair else { return }
            guard pair.isValid else {
                state.clear()
                return
            }
            let primaryHeight = self.screenService.primaryScreenHeight
            pair.updateRatioFromCursor(cursorCoordinate: cursorCoordinate, primaryScreenHeight: primaryHeight)
            state.dividerWindow.update(for: pair)
        }

        state.dividerWindow.onDividerReleased = {
            // Arraste finalizado; proporção salva no pair
        }
    }

    /// Retorna o par ativo no monitor sob o cursor (ou o primeiro disponível para compatibilidade).
    public var activePair: PairedSplit? {
        if let currentScreen = screenService.screenContaining(point: NSEvent.mouseLocation) {
            return statesByScreen[currentScreen.displayID]?.pair
        }
        return statesByScreen.values.compactMap { $0.pair }.first
    }

    /// Retorna todos os pares ativos mantidos através de todos os monitores conectados.
    public var activePairs: [PairedSplit] {
        return statesByScreen.values.compactMap { $0.pair }
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

    /// Registra uma nova janela que sofreu snap e ativa o divisor caso haja uma parceira oposta no monitor específico.
    public func registerSnap(window: WindowElement, zone: SnapZone, screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let screenState = state(for: screen)

        // 1. Tenta emparelhar dinamicamente usando a parceira detectada na intercessão desta tela
        if let flush = calculateFlushTargetRect(for: zone, screen: screen, windowToExclude: window) {
            if flush.orientation == .vertical {
                if zone == .topHalf || zone == .topThird || zone == .topTwoThirds {
                    screenState.recentTopWindow = window
                    screenState.recentBottomWindow = flush.partner
                    createVerticalPair(top: window, bottom: flush.partner, ratio: flush.ratio, visibleFrame: visibleFrame, in: screenState)
                } else {
                    screenState.recentTopWindow = flush.partner
                    screenState.recentBottomWindow = window
                    createVerticalPair(top: flush.partner, bottom: window, ratio: flush.ratio, visibleFrame: visibleFrame, in: screenState)
                }
            } else {
                if zone == .leftHalf || zone == .leftOneThird || zone == .leftThird || zone == .leftTwoThirds {
                    screenState.recentLeftWindow = window
                    screenState.recentRightWindow = flush.partner
                    createHorizontalPair(left: window, right: flush.partner, ratio: flush.ratio, visibleFrame: visibleFrame, in: screenState)
                } else {
                    screenState.recentLeftWindow = flush.partner
                    screenState.recentRightWindow = window
                    createHorizontalPair(left: flush.partner, right: window, ratio: flush.ratio, visibleFrame: visibleFrame, in: screenState)
                }
            }
            return
        }

        // 2. Fallback de histórico recente isolado para esta tela
        switch zone {
        case .leftHalf, .leftOneThird, .leftThird, .leftTwoThirds:
            screenState.recentLeftWindow = window
            if let right = screenState.recentRightWindow {
                createHorizontalPair(left: window, right: right, ratio: 0.5, visibleFrame: visibleFrame, in: screenState)
            }

        case .rightHalf, .rightOneThird, .rightTwoThirds:
            screenState.recentRightWindow = window
            if let left = screenState.recentLeftWindow {
                createHorizontalPair(left: left, right: window, ratio: 0.5, visibleFrame: visibleFrame, in: screenState)
            }

        case .topHalf, .topThird, .topTwoThirds:
            screenState.recentTopWindow = window
            if let bottom = screenState.recentBottomWindow {
                createVerticalPair(top: window, bottom: bottom, ratio: 0.5, visibleFrame: visibleFrame, in: screenState)
            }

        case .bottomHalf, .bottomThird, .bottomTwoThirds:
            screenState.recentBottomWindow = window
            if let top = screenState.recentTopWindow {
                createVerticalPair(top: top, bottom: window, ratio: 0.5, visibleFrame: visibleFrame, in: screenState)
            }

        case .maximize:
            screenState.clear()

        default:
            screenState.clear()
        }
    }

    private func createHorizontalPair(
        left: WindowElement,
        right: WindowElement,
        ratio: CGFloat,
        visibleFrame: CGRect,
        in screenState: ScreenPairState
    ) {
        guard left.rawElement != right.rawElement else { return }
        let pair = PairedSplit(
            firstWindow: left,
            secondWindow: right,
            orientation: .horizontal,
            visibleFrame: visibleFrame,
            ratio: ratio
        )
        screenState.pair = pair
        screenState.dividerWindow.update(for: pair)
    }

    private func createVerticalPair(
        top: WindowElement,
        bottom: WindowElement,
        ratio: CGFloat,
        visibleFrame: CGRect,
        in screenState: ScreenPairState
    ) {
        guard top.rawElement != bottom.rawElement else { return }
        let pair = PairedSplit(
            firstWindow: top,
            secondWindow: bottom,
            orientation: .vertical,
            visibleFrame: visibleFrame,
            ratio: ratio
        )
        screenState.pair = pair
        screenState.dividerWindow.update(for: pair)
    }

    /// Força o emparelhamento explícito de duas janelas conhecidas na tela especificada.
    public func pair(
        first: WindowElement,
        second: WindowElement,
        orientation: SplitOrientation,
        on screen: NSScreen,
        ratio: CGFloat = 0.5
    ) {
        let screenState = state(for: screen)
        let pair = PairedSplit(
            firstWindow: first,
            secondWindow: second,
            orientation: orientation,
            visibleFrame: screen.visibleFrame,
            ratio: ratio
        )
        screenState.pair = pair
        let primaryHeight = screenService.primaryScreenHeight
        pair.applyCurrentSplit(primaryScreenHeight: primaryHeight)
        screenState.dividerWindow.update(for: pair)
    }

    /// Remove a barra divisória e desfaz o vínculo de emparelhamento ativo (de uma tela específica ou de todas).
    public func clearPairing(for screen: NSScreen? = nil) {
        if let screen = screen {
            statesByScreen[screen.displayID]?.clear()
            statesByScreen.removeValue(forKey: screen.displayID)
        } else {
            for (_, state) in statesByScreen {
                state.clear()
            }
            statesByScreen.removeAll()
        }
    }
}
