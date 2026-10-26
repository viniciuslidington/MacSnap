import Cocoa
import QuartzCore

/// Estados visuais da barra flutuante de layouts (estilo Windows 11 Snap Flyout).
public enum BarPresentationState: Equatable, Sendable {
    case hidden
    case pill
    case expanded
}

/// Barra flutuante de layouts (estilo Snap Bar do Windows 11) que se desdobra
/// no topo da tela quando o usuário arrasta uma janela:
/// 1. Surge primeiro como uma pílula achatada e discreta (Pill Mode).
/// 2. Ao passar o cursor por cima, expande fluidamente revelando os cartões de layout.
@MainActor
public final class SnapLayoutBarWindow: NSPanel {
    private let barView = SnapLayoutBarView()
    public private(set) var presentationState: BarPresentationState = .hidden
    public private(set) var currentScreen: NSScreen?

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        // Nível superior ao PreviewOverlayWindow para garantir que a barra de layouts nunca fique encoberta
        self.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 25)
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        self.contentView = barView
    }

    /// Exibe a pílula achatada e discreta (Pill Mode) no topo da tela.
    public func presentPill(on screen: NSScreen, animated: Bool = true) {
        if presentationState == .pill && currentScreen == screen { return }

        let screenChanged = (currentScreen != screen)
        currentScreen = screen
        presentationState = .pill
        barView.presentationState = .pill
        barView.isPortrait = screen.isPortrait

        let visible = screen.visibleFrame
        let pillW: CGFloat = 220.0
        let pillH: CGFloat = 24.0
        let x = visible.origin.x + (visible.width - pillW) / 2.0
        let targetY = visible.origin.y + visible.height - pillH - 4.0
        let targetFrame = CGRect(x: x, y: targetY, width: pillW, height: pillH)

        if self.isVisible && screenChanged {
            // Transição suave entre monitores: reposiciona no topo do novo monitor onde o mouse está
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().setFrame(targetFrame, display: true)
                }
            } else {
                self.setFrame(targetFrame, display: true)
            }
        } else if !self.isVisible {
            if animated {
                let startY = visible.origin.y + visible.height + 10.0
                self.setFrame(CGRect(x: x, y: startY, width: pillW, height: pillH), display: true)
                self.alphaValue = 0.0
                self.orderFrontRegardless()

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().setFrame(targetFrame, display: true)
                    self.animator().alphaValue = 1.0
                }
            } else {
                self.setFrame(targetFrame, display: true)
                self.alphaValue = 1.0
                self.orderFrontRegardless()
            }
        } else {
            self.setFrame(targetFrame, display: true)
            self.alphaValue = 1.0
        }
        self.invalidateShadow()
    }

    /// Expande suavemente da pílula para a barra completa ao detectar hover.
    public func expand(animated: Bool = true) {
        guard presentationState == .pill, let screen = currentScreen else { return }
        presentationState = .expanded
        barView.presentationState = .expanded

        let isPortrait = screen.isPortrait
        let visible = screen.visibleFrame
        let maxAllowedWidth = isPortrait ? 500.0 : 680.0
        let barWidth: CGFloat = min(visible.width - 32, maxAllowedWidth)
        let barHeight: CGFloat = 94.0

        let x = visible.origin.x + (visible.width - barWidth) / 2.0
        let targetY = visible.origin.y + visible.height - barHeight - 8.0
        let targetFrame = CGRect(x: x, y: targetY, width: barWidth, height: barHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(targetFrame, display: true)
            }
        } else {
            self.setFrame(targetFrame, display: true)
        }
        self.invalidateShadow()
    }

    /// Recolhe suavemente a barra de layouts de volta para o modo pílula achatada.
    public func collapseToPill(animated: Bool = true) {
        guard presentationState == .expanded, let screen = currentScreen else { return }
        presentationState = .pill
        barView.presentationState = .pill
        barView.resetHover()

        let visible = screen.visibleFrame
        let pillW: CGFloat = 220.0
        let pillH: CGFloat = 24.0
        let x = visible.origin.x + (visible.width - pillW) / 2.0
        let targetY = visible.origin.y + visible.height - pillH - 4.0
        let targetFrame = CGRect(x: x, y: targetY, width: pillW, height: pillH)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(targetFrame, display: true)
            }
        } else {
            self.setFrame(targetFrame, display: true)
        }
        self.invalidateShadow()
    }

    /// Exibe diretamente em modo expandido (mantido para compatibilidade e testes).
    public func present(on screen: NSScreen, animated: Bool = true) {
        if presentationState == .expanded && currentScreen == screen { return }
        currentScreen = screen
        presentationState = .expanded
        barView.presentationState = .expanded
        barView.isPortrait = screen.isPortrait

        let isPortrait = screen.isPortrait
        let visible = screen.visibleFrame
        let maxAllowedWidth = isPortrait ? 500.0 : 680.0
        let barWidth: CGFloat = min(visible.width - 32, maxAllowedWidth)
        let barHeight: CGFloat = 94.0

        let x = visible.origin.x + (visible.width - barWidth) / 2.0
        let targetY = visible.origin.y + visible.height - barHeight - 8.0
        let targetFrame = CGRect(x: x, y: targetY, width: barWidth, height: barHeight)

        if !self.isVisible {
            if animated {
                let startY = visible.origin.y + visible.height + 20.0
                self.setFrame(CGRect(x: x, y: startY, width: barWidth, height: barHeight), display: true)
                self.alphaValue = 0.0
                self.orderFrontRegardless()

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.20
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().setFrame(targetFrame, display: true)
                    self.animator().alphaValue = 1.0
                }
            } else {
                self.setFrame(targetFrame, display: true)
                self.alphaValue = 1.0
                self.orderFrontRegardless()
            }
        } else {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.20
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().setFrame(targetFrame, display: true)
                }
            } else {
                self.setFrame(targetFrame, display: true)
            }
        }
        self.invalidateShadow()
    }

    /// Esconde a barra ou pílula com animação suave.
    public func dismiss(animated: Bool = true) {
        guard presentationState != .hidden else { return }
        presentationState = .hidden
        currentScreen = nil
        barView.resetHover()

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                self.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, self.presentationState == .hidden else { return }
                    self.orderOut(nil)
                    self.barView.presentationState = .hidden
                }
            })
        } else {
            self.alphaValue = 0.0
            self.orderOut(nil)
            self.barView.presentationState = .hidden
        }
    }

    /// Orientação dos cartões de layout.
    public var isPortrait: Bool {
        get { barView.isPortrait }
        set { barView.isPortrait = newValue }
    }

    /// Retorna o ID do slot atualmente sob o cursor.
    public var currentlyHoveredSlotID: Int? {
        barView.currentlyHoveredSlotID
    }

    /// Retorna o número total de slots configurados no modal.
    public var totalSlotsCount: Int {
        barView.totalSlotsCount
    }

    /// Retorna o rect de um slot específico pelo índice (em coordenadas locais da view).
    public func slotRect(at index: Int) -> CGRect? {
        barView.slotRect(at: index)
    }

    /// Atualiza qual slot está sob o cursor e retorna a `SnapZone` correspondente, se houver.
    /// Se estiver no modo pílula e o cursor estiver sobre a pílula, expande automaticamente.
    public func checkHover(at globalPoint: CGPoint) -> SnapZone? {
        guard presentationState != .hidden else { return nil }

        if presentationState == .pill {
            let hitArea = self.frame.insetBy(dx: -30, dy: -20)
            if hitArea.contains(globalPoint) {
                expand()
            }
            return nil
        }

        let windowPoint = self.convertPoint(fromScreen: globalPoint)
        let localPoint = self.contentView?.convert(windowPoint, from: nil) ?? .zero
        let zone = barView.updateHover(at: localPoint)
        return zone
    }
}

/// View com o desenho visual translúcido dos cards de layout no estilo Apple Glass UI.
final class SnapLayoutBarView: NSView {
    struct LayoutCard {
        let id: Int
        let rect: CGRect
    }

    struct LayoutSlot {
        let id: Int
        let cardId: Int
        let rect: CGRect
        let zone: SnapZone
    }

    var presentationState: BarPresentationState = .hidden {
        didSet {
            let cr: CGFloat = (presentationState == .pill) ? 12.0 : 16.0
            layer?.cornerRadius = cr
            visualEffectView.layer?.cornerRadius = cr
            rebuildSlots()
            canvasView.needsDisplay = true
        }
    }

    var isPortrait: Bool = false {
        didSet {
            rebuildSlots()
            canvasView.needsDisplay = true
        }
    }

    private let visualEffectView = NSVisualEffectView()
    private let canvasView = SnapBarCanvasView()
    private var cards: [LayoutCard] = []
    private var slots: [LayoutSlot] = []
    private var hoveredSlotID: Int?

    var currentlyHoveredSlotID: Int? {
        hoveredSlotID
    }

    var totalSlotsCount: Int {
        slots.count
    }

    func slotRect(at index: Int) -> CGRect? {
        guard index >= 0 && index < slots.count else { return nil }
        return slots[index].rect
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupGlassBacking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGlassBacking()
    }

    private func setupGlassBacking() {
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true

        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.alphaValue = 0.85
        addSubview(visualEffectView)

        canvasView.onDraw = { [weak self] rect in
            self?.drawCanvas(in: rect)
        }
        addSubview(canvasView)
    }

    override func layout() {
        super.layout()
        visualEffectView.frame = bounds
        canvasView.frame = bounds
        let cr: CGFloat = (presentationState == .pill) ? 12.0 : 16.0
        layer?.cornerRadius = cr
        visualEffectView.layer?.cornerRadius = cr
        rebuildSlots()
        canvasView.needsDisplay = true
    }

    func resetHover() {
        if hoveredSlotID != nil {
            hoveredSlotID = nil
            canvasView.needsDisplay = true
        }
    }

    func updateHover(at point: CGPoint) -> SnapZone? {
        guard presentationState == .expanded else { return nil }

        for slot in slots {
            if slot.rect.contains(point) {
                if hoveredSlotID != slot.id {
                    hoveredSlotID = slot.id
                    canvasView.needsDisplay = true
                }
                return slot.zone
            }
        }

        if hoveredSlotID != nil {
            hoveredSlotID = nil
            canvasView.needsDisplay = true
        }
        return nil
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        rebuildSlots()
    }

    func rebuildSlots() {
        cards.removeAll()
        slots.removeAll()
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }

        // Se estiver em modo pílula, não monta cartões
        guard presentationState == .expanded else { return }

        let cardHeight: CGFloat = 74.0

        if isPortrait {
            buildVerticalSlots(cardHeight: cardHeight, marginH: 16.0, gutter: 16.0)
        } else {
            buildHorizontalSlots(cardHeight: cardHeight, marginH: 16.0, gutter: 14.0)
        }
    }

    // MARK: - Cartões para Telas Horizontais (16:9 / Ultrawide)
    private func buildHorizontalSlots(cardHeight: CGFloat, marginH: CGFloat, gutter: CGFloat) {
        let cardCount: CGFloat = 6.0
        let availableW = bounds.width - (marginH * 2) - (gutter * (cardCount - 1))
        let cardW = max(20.0, availableW / cardCount)
        let cardH = cardHeight
        let startY = (bounds.height - cardH) / 2.0

        func addCard(index: Int) -> CGRect {
            let cX = marginH + CGFloat(index) * (cardW + gutter)
            let r = CGRect(x: cX, y: startY, width: cardW, height: cardH)
            cards.append(LayoutCard(id: index, rect: r))
            return r
        }

        func addSlot(cardId: Int, rect: CGRect, zone: SnapZone) {
            slots.append(LayoutSlot(id: slots.count, cardId: cardId, rect: rect, zone: zone))
        }

        // 1. Duas Colunas (50 / 50)
        let c0Rect = addCard(index: 0)
        let c0Inner = c0Rect.insetBy(dx: 4, dy: 4)
        let c0ColW = (c0Inner.width - 2.0) / 2.0
        addSlot(cardId: 0, rect: CGRect(x: c0Inner.minX, y: c0Inner.minY, width: c0ColW, height: c0Inner.height), zone: .leftHalf)
        addSlot(cardId: 0, rect: CGRect(x: c0Inner.minX + c0ColW + 2.0, y: c0Inner.minY, width: c0ColW, height: c0Inner.height), zone: .rightHalf)

        // 2. Três Colunas (1/3 / 1/3 / 1/3)
        let c1Rect = addCard(index: 1)
        let c1Inner = c1Rect.insetBy(dx: 4, dy: 4)
        let c1ColW = (c1Inner.width - 4.0) / 3.0
        addSlot(cardId: 1, rect: CGRect(x: c1Inner.minX, y: c1Inner.minY, width: c1ColW, height: c1Inner.height), zone: .leftThird)
        addSlot(cardId: 1, rect: CGRect(x: c1Inner.minX + c1ColW + 2.0, y: c1Inner.minY, width: c1ColW, height: c1Inner.height), zone: .centerThird)
        addSlot(cardId: 1, rect: CGRect(x: c1Inner.minX + (c1ColW * 2) + 4.0, y: c1Inner.minY, width: c1ColW, height: c1Inner.height), zone: .rightThird)

        // 3. Assimétrico (2/3 + 1/3)
        let c2Rect = addCard(index: 2)
        let c2Inner = c2Rect.insetBy(dx: 4, dy: 4)
        let c2TwoThirdsW = (c2Inner.width - 2.0) * (2.0 / 3.0)
        let c2OneThirdW = (c2Inner.width - 2.0) - c2TwoThirdsW
        addSlot(cardId: 2, rect: CGRect(x: c2Inner.minX, y: c2Inner.minY, width: c2TwoThirdsW, height: c2Inner.height), zone: .leftTwoThirds)
        addSlot(cardId: 2, rect: CGRect(x: c2Inner.minX + c2TwoThirdsW + 2.0, y: c2Inner.minY, width: c2OneThirdW, height: c2Inner.height), zone: .rightOneThird)

        // 4. Assimétrico Invertido (1/3 + 2/3)
        let c3Rect = addCard(index: 3)
        let c3Inner = c3Rect.insetBy(dx: 4, dy: 4)
        let c3OneThirdW = (c3Inner.width - 2.0) * (1.0 / 3.0)
        let c3TwoThirdsW = (c3Inner.width - 2.0) - c3OneThirdW
        addSlot(cardId: 3, rect: CGRect(x: c3Inner.minX, y: c3Inner.minY, width: c3OneThirdW, height: c3Inner.height), zone: .leftOneThird)
        addSlot(cardId: 3, rect: CGRect(x: c3Inner.minX + c3OneThirdW + 2.0, y: c3Inner.minY, width: c3TwoThirdsW, height: c3Inner.height), zone: .rightTwoThirds)

        // 5. Quatro Quadrantes (2x2)
        let c4Rect = addCard(index: 4)
        let c4Inner = c4Rect.insetBy(dx: 4, dy: 4)
        let qW = (c4Inner.width - 2.0) / 2.0
        let qH = (c4Inner.height - 2.0) / 2.0
        addSlot(cardId: 4, rect: CGRect(x: c4Inner.minX, y: c4Inner.minY + qH + 2.0, width: qW, height: qH), zone: .topLeftQuarter)
        addSlot(cardId: 4, rect: CGRect(x: c4Inner.minX + qW + 2.0, y: c4Inner.minY + qH + 2.0, width: qW, height: qH), zone: .topRightQuarter)
        addSlot(cardId: 4, rect: CGRect(x: c4Inner.minX, y: c4Inner.minY, width: qW, height: qH), zone: .bottomLeftQuarter)
        addSlot(cardId: 4, rect: CGRect(x: c4Inner.minX + qW + 2.0, y: c4Inner.minY, width: qW, height: qH), zone: .bottomRightQuarter)

        // 6. Maximizar
        let c5Rect = addCard(index: 5)
        let c5Inner = c5Rect.insetBy(dx: 4, dy: 4)
        addSlot(cardId: 5, rect: c5Inner, zone: .maximize)
    }

    // MARK: - Cartões para Telas Verticais (Portrait)
    private func buildVerticalSlots(cardHeight: CGFloat, marginH: CGFloat, gutter: CGFloat) {
        let cardCount: CGFloat = 5.0
        let availableW = bounds.width - (marginH * 2) - (gutter * (cardCount - 1))
        let cardW = max(20.0, availableW / cardCount)
        let cardH = cardHeight
        let startY = (bounds.height - cardH) / 2.0

        func addCard(index: Int) -> CGRect {
            let cX = marginH + CGFloat(index) * (cardW + gutter)
            let r = CGRect(x: cX, y: startY, width: cardW, height: cardH)
            cards.append(LayoutCard(id: index, rect: r))
            return r
        }

        func addSlot(cardId: Int, rect: CGRect, zone: SnapZone) {
            slots.append(LayoutSlot(id: slots.count, cardId: cardId, rect: rect, zone: zone))
        }

        // 1. Metades Verticais (Topo / Base)
        let c0Rect = addCard(index: 0)
        let c0Inner = c0Rect.insetBy(dx: 4, dy: 4)
        let halfH = (c0Inner.height - 2.0) / 2.0
        addSlot(cardId: 0, rect: CGRect(x: c0Inner.minX, y: c0Inner.minY + halfH + 2.0, width: c0Inner.width, height: halfH), zone: .topHalf)
        addSlot(cardId: 0, rect: CGRect(x: c0Inner.minX, y: c0Inner.minY, width: c0Inner.width, height: halfH), zone: .bottomHalf)

        // 2. Terços Verticais (Topo / Centro / Base)
        let c1Rect = addCard(index: 1)
        let c1Inner = c1Rect.insetBy(dx: 4, dy: 4)
        let thirdH = (c1Inner.height - 4.0) / 3.0
        addSlot(cardId: 1, rect: CGRect(x: c1Inner.minX, y: c1Inner.minY + (thirdH * 2) + 4.0, width: c1Inner.width, height: thirdH), zone: .topThird)
        addSlot(cardId: 1, rect: CGRect(x: c1Inner.minX, y: c1Inner.minY + thirdH + 2.0, width: c1Inner.width, height: thirdH), zone: .middleThird)
        addSlot(cardId: 1, rect: CGRect(x: c1Inner.minX, y: c1Inner.minY, width: c1Inner.width, height: thirdH), zone: .bottomThird)

        // 3. Dois Terços (2/3 Topo + 1/3 Base)
        let c2Rect = addCard(index: 2)
        let c2Inner = c2Rect.insetBy(dx: 4, dy: 4)
        let twoThirdsH = (c2Inner.height - 2.0) * (2.0 / 3.0)
        let oneThirdH = (c2Inner.height - 2.0) - twoThirdsH
        addSlot(cardId: 2, rect: CGRect(x: c2Inner.minX, y: c2Inner.minY + oneThirdH + 2.0, width: c2Inner.width, height: twoThirdsH), zone: .topTwoThirds)
        addSlot(cardId: 2, rect: CGRect(x: c2Inner.minX, y: c2Inner.minY, width: c2Inner.width, height: oneThirdH), zone: .bottomThird)

        // 4. Invertido (1/3 Topo + 2/3 Base)
        let c3Rect = addCard(index: 3)
        let c3Inner = c3Rect.insetBy(dx: 4, dy: 4)
        addSlot(cardId: 3, rect: CGRect(x: c3Inner.minX, y: c3Inner.minY + twoThirdsH + 2.0, width: c3Inner.width, height: oneThirdH), zone: .topThird)
        addSlot(cardId: 3, rect: CGRect(x: c3Inner.minX, y: c3Inner.minY, width: c3Inner.width, height: twoThirdsH), zone: .bottomTwoThirds)

        // 5. Maximizar
        let c4Rect = addCard(index: 4)
        let c4Inner = c4Rect.insetBy(dx: 4, dy: 4)
        addSlot(cardId: 4, rect: c4Inner, zone: .maximize)
    }

    func drawCanvas(in dirtyRect: NSRect) {
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)

        if presentationState == .pill {
            // MODO PÍLULA ACHATADA: Design premium Apple Glass no topo da tela com alta transparência
            let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)

            // Fundo translúcido com profundidade (Apple Glass refinado)
            let containerTint = isDark
                ? NSColor(white: 0.12, alpha: 0.35)
                : NSColor(white: 1.0, alpha: 0.45)
            containerTint.setFill()
            bgPath.fill()

            // Borda externa fina de alta definição
            let containerRim = isDark
                ? NSColor(white: 1.0, alpha: 0.22)
                : NSColor(white: 0.0, alpha: 0.12)
            containerRim.setStroke()
            bgPath.lineWidth = 1.0
            bgPath.stroke()

            // Linha especular superior simulando reflexo de luz no topo do vidro chanfrado
            let topHighlightPath = NSBezierPath()
            let highlightY = bounds.maxY - 1.5
            topHighlightPath.move(to: CGPoint(x: bounds.minX + 16, y: highlightY))
            topHighlightPath.line(to: CGPoint(x: bounds.maxX - 16, y: highlightY))
            let highlightColor = isDark
                ? NSColor(white: 1.0, alpha: 0.35)
                : NSColor(white: 1.0, alpha: 0.70)
            highlightColor.setStroke()
            topHighlightPath.lineWidth = 1.0
            topHighlightPath.stroke()

            // GLIFO VETORIAL DE SNAP LAYOUTS NO CENTRO DA PÍLULA:
            // Desenha um emblema geométrico composto por mini painéis de divisão de tela
            // e um sutil chevron para baixo indicando que a barra expande ao aproximar o cursor
            let iconW: CGFloat = 24.0
            let iconH: CGFloat = 12.0
            let gap: CGFloat = 7.0
            let chevronW: CGFloat = 7.0
            let totalContentW = iconW + gap + chevronW
            let startX = bounds.midX - (totalContentW / 2.0)
            let iconY = bounds.midY - (iconH / 2.0)

            // Miniatura de Layout de Janela (Dois painéis lado a lado)
            let paneW: CGFloat = (iconW - 2.5) / 2.0
            let leftPaneRect = CGRect(x: startX, y: iconY, width: paneW, height: iconH)
            let rightPaneRect = CGRect(x: startX + paneW + 2.5, y: iconY, width: paneW, height: iconH)

            let tileFill = isDark
                ? NSColor(white: 1.0, alpha: 0.10)
                : NSColor(white: 0.0, alpha: 0.05)
            let tileStroke = isDark
                ? NSColor(white: 1.0, alpha: 0.50)
                : NSColor(white: 0.18, alpha: 0.40)

            let leftPath = NSBezierPath(roundedRect: leftPaneRect, xRadius: 2.0, yRadius: 2.0)
            tileFill.setFill()
            leftPath.fill()
            tileStroke.setStroke()
            leftPath.lineWidth = 1.0
            leftPath.stroke()

            let rightPath = NSBezierPath(roundedRect: rightPaneRect, xRadius: 2.0, yRadius: 2.0)
            tileFill.setFill()
            rightPath.fill()
            tileStroke.setStroke()
            rightPath.lineWidth = 1.0
            rightPath.stroke()

            // Sutil Chevron Indicador de Expansão (⌵)
            let chevronStartX = startX + iconW + gap
            let chevronMidY = bounds.midY
            let chevronPath = NSBezierPath()
            chevronPath.move(to: CGPoint(x: chevronStartX, y: chevronMidY + 2.2))
            chevronPath.line(to: CGPoint(x: chevronStartX + (chevronW / 2.0), y: chevronMidY - 2.2))
            chevronPath.line(to: CGPoint(x: chevronStartX + chevronW, y: chevronMidY + 2.2))
            chevronPath.lineCapStyle = .round
            chevronPath.lineJoinStyle = .round
            let chevronColor = isDark
                ? NSColor(white: 1.0, alpha: 0.50)
                : NSColor(white: 0.20, alpha: 0.40)
            chevronColor.setStroke()
            chevronPath.lineWidth = 1.4
            chevronPath.stroke()

            return
        }

        // MODO EXPANDIDO: Menu completo com cartões espaçados e alta translucidez
        if slots.isEmpty { rebuildSlots() }

        // 1. Container geral Apple Glass translúcido
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        let containerTint = isDark
            ? NSColor(white: 0.12, alpha: 0.25)
            : NSColor(white: 1.0, alpha: 0.38)
        containerTint.setFill()
        bgPath.fill()

        let containerRim = isDark
            ? NSColor(white: 1.0, alpha: 0.22)
            : NSColor(white: 0.0, alpha: 0.12)
        containerRim.setStroke()
        bgPath.lineWidth = 1.0
        bgPath.stroke()

        // 2. Desenho de cada CARTÃO (Miniatura de tela delimitada com fundo e borda sutil)
        for card in cards {
            let cardPath = NSBezierPath(roundedRect: card.rect, xRadius: 8, yRadius: 8)
            let cardTint = isDark
                ? NSColor(white: 1.0, alpha: 0.04)
                : NSColor(white: 0.0, alpha: 0.03)
            cardTint.setFill()
            cardPath.fill()

            let cardRim = isDark
                ? NSColor(white: 1.0, alpha: 0.14)
                : NSColor(white: 0.0, alpha: 0.08)
            cardRim.setStroke()
            cardPath.lineWidth = 1.0
            cardPath.stroke()
        }

        // 3. Desenho de cada SLOT geométrico sem poluição de textos
        for slot in slots {
            let isHovered = (slot.id == hoveredSlotID)
            let slotPath = NSBezierPath(roundedRect: slot.rect, xRadius: 5, yRadius: 5)

            if isHovered {
                // Estado Hover: Vidro translúcido cinza claro iluminado (Apple Glass)
                let hoverFill = isDark
                    ? NSColor(white: 1.0, alpha: 0.32)
                    : NSColor(white: 0.88, alpha: 0.45)
                hoverFill.setFill()
                slotPath.fill()

                // Borda especular de alto contraste
                let hoverStroke = isDark
                    ? NSColor.white
                    : NSColor(white: 0.10, alpha: 0.90)
                hoverStroke.setStroke()
                slotPath.lineWidth = 2.0
                slotPath.stroke()

                // Brilho especular interno
                let innerSlotRect = slot.rect.insetBy(dx: 1.0, dy: 1.0)
                if innerSlotRect.width > 0 && innerSlotRect.height > 0 {
                    let innerSlotPath = NSBezierPath(roundedRect: innerSlotRect, xRadius: 4, yRadius: 4)
                    let innerGlow = isDark
                        ? NSColor(white: 1.0, alpha: 0.25)
                        : NSColor(white: 1.0, alpha: 0.55)
                    innerGlow.setStroke()
                    innerSlotPath.lineWidth = 0.8
                    innerSlotPath.stroke()
                }
            } else {
                // Estado Normal: Placa interna neutra suave
                let normalFill = isDark
                    ? NSColor(white: 1.0, alpha: 0.05)
                    : NSColor(white: 0.0, alpha: 0.03)
                normalFill.setFill()
                slotPath.fill()

                let normalStroke = isDark
                    ? NSColor(white: 1.0, alpha: 0.16)
                    : NSColor(white: 0.0, alpha: 0.10)
                normalStroke.setStroke()
                slotPath.lineWidth = 1.0
                slotPath.stroke()
            }
        }
    }
}

/// Canvas overlay para desenho dos cartões sobre o NSVisualEffectView sem sofrer oclusão de camadas.
final class SnapBarCanvasView: NSView {
    var onDraw: ((NSRect) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        onDraw?(dirtyRect)
    }
}
