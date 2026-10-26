import Cocoa
import QuartzCore

/// Barra flutuante de layouts (estilo Snap Bar do Windows 11) que se desdobra
/// no topo da tela quando o usuário arrasta uma janela, oferecendo templates
/// adaptativos e interativos tanto para telas horizontais (16:9) quanto verticais.
@MainActor
public final class SnapLayoutBarWindow: NSPanel {
    private let barView = SnapLayoutBarView()
    private var isPresented = false

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        self.contentView = barView
    }

    /// Exibe a barra de layouts no topo da tela indicada adaptando os cartões à orientação da tela.
    public func present(on screen: NSScreen) {
        guard !isPresented else { return }
        isPresented = true

        let isPortrait = screen.isPortrait
        barView.isPortrait = isPortrait

        let visible = screen.visibleFrame
        let maxAllowedWidth = isPortrait ? 520.0 : 720.0
        let barWidth: CGFloat = min(visible.width - 40, maxAllowedWidth)
        let barHeight: CGFloat = 88.0

        let x = visible.origin.x + (visible.width - barWidth) / 2.0
        let targetY = visible.origin.y + visible.height - barHeight - 8
        let startY = visible.origin.y + visible.height + 20 // começa acima da tela para deslizar

        self.setFrame(CGRect(x: x, y: startY, width: barWidth, height: barHeight), display: true)
        self.alphaValue = 0.0
        self.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(CGRect(x: x, y: targetY, width: barWidth, height: barHeight), display: true)
            self.animator().alphaValue = 1.0
        }
    }

    /// Esconde a barra com animação suave.
    public func dismiss() {
        guard isPresented else { return }
        isPresented = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.orderOut(nil)
                self?.barView.resetHover()
            }
        })
    }

    /// Atualiza qual slot está sob o cursor e retorna a `SnapZone` correspondente, se houver.
    public func checkHover(at globalPoint: CGPoint) -> SnapZone? {
        guard isPresented else { return nil }

        // Converte corretamente de Coordenadas de Tela -> Coordenadas da Janela -> Coordenadas da View
        let windowPoint = self.convertPoint(fromScreen: globalPoint)
        let localPoint = self.contentView?.convert(windowPoint, from: nil) ?? .zero
        let zone = barView.updateHover(at: localPoint)
        return zone
    }
}

/// View com o desenho visual translúcido dos cards de layout no estilo Apple Glass UI.
final class SnapLayoutBarView: NSView {
    private struct LayoutSlot {
        let rect: CGRect
        let zone: SnapZone
        let label: String
    }

    var isPortrait: Bool = false {
        didSet {
            rebuildSlots()
            canvasView.needsDisplay = true
        }
    }

    private let visualEffectView = NSVisualEffectView()
    private let canvasView = SnapBarCanvasView()
    private var slots: [LayoutSlot] = []
    private var hoveredZone: SnapZone?

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
        rebuildSlots()
        canvasView.needsDisplay = true
    }

    func resetHover() {
        hoveredZone = nil
        canvasView.needsDisplay = true
    }

    func updateHover(at point: CGPoint) -> SnapZone? {
        for slot in slots {
            if slot.rect.contains(point) {
                if hoveredZone != slot.zone {
                    hoveredZone = slot.zone
                    canvasView.needsDisplay = true
                }
                return slot.zone
            }
        }

        if hoveredZone != nil {
            hoveredZone = nil
            canvasView.needsDisplay = true
        }
        return nil
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        rebuildSlots()
    }

    func rebuildSlots() {
        slots.removeAll()
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }

        let padding: CGFloat = 8.0
        let cardHeight = b.height - (padding * 2)

        if isPortrait {
            buildVerticalSlots(cardHeight: cardHeight, padding: padding)
        } else {
            buildHorizontalSlots(cardHeight: cardHeight, padding: padding)
        }
    }

    // MARK: - Cartões para Telas Horizontais (16:9 / Ultrawide)
    private func buildHorizontalSlots(cardHeight: CGFloat, padding: CGFloat) {
        let cardCount: CGFloat = 6.0
        let availableWidth = bounds.width - (padding * (cardCount + 1))
        let cardWidth = availableWidth / cardCount

        // 1. Duas Colunas (50 / 50)
        let c1X = padding
        let halfColW = (cardWidth - 3) / 2.0
        slots.append(LayoutSlot(
            rect: CGRect(x: c1X, y: padding, width: halfColW, height: cardHeight),
            zone: .leftHalf,
            label: "Esq 1/2"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c1X + halfColW + 3, y: padding, width: halfColW, height: cardHeight),
            zone: .rightHalf,
            label: "Dir 1/2"
        ))

        // 2. Três Colunas (1/3 / 1/3 / 1/3)
        let c2X = c1X + cardWidth + padding
        let thirdColW = (cardWidth - 4) / 3.0
        slots.append(LayoutSlot(
            rect: CGRect(x: c2X, y: padding, width: thirdColW, height: cardHeight),
            zone: .leftThird,
            label: "1/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c2X + thirdColW + 2, y: padding, width: thirdColW, height: cardHeight),
            zone: .centerThird,
            label: "1/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c2X + (thirdColW * 2) + 4, y: padding, width: thirdColW, height: cardHeight),
            zone: .rightThird,
            label: "1/3"
        ))

        // 3. Assimétrico (2/3 + 1/3)
        let c3X = c2X + cardWidth + padding
        let twoThirdsColW = (cardWidth - 3) * (2.0 / 3.0)
        let oneThirdColW = (cardWidth - 3) - twoThirdsColW
        slots.append(LayoutSlot(
            rect: CGRect(x: c3X, y: padding, width: twoThirdsColW, height: cardHeight),
            zone: .leftTwoThirds,
            label: "Esq 2/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c3X + twoThirdsColW + 3, y: padding, width: oneThirdColW, height: cardHeight),
            zone: .rightOneThird,
            label: "1/3"
        ))

        // 4. Assimétrico Invertido (1/3 + 2/3)
        let c4X = c3X + cardWidth + padding
        slots.append(LayoutSlot(
            rect: CGRect(x: c4X, y: padding, width: oneThirdColW, height: cardHeight),
            zone: .leftOneThird,
            label: "1/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c4X + oneThirdColW + 3, y: padding, width: twoThirdsColW, height: cardHeight),
            zone: .rightTwoThirds,
            label: "Dir 2/3"
        ))

        // 5. Quatro Quadrantes (2x2)
        let c5X = c4X + cardWidth + padding
        let qW = (cardWidth - 3) / 2.0
        let qH = (cardHeight - 3) / 2.0
        slots.append(LayoutSlot(
            rect: CGRect(x: c5X, y: padding + qH + 3, width: qW, height: qH),
            zone: .topLeftQuarter,
            label: "TL"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c5X + qW + 3, y: padding + qH + 3, width: qW, height: qH),
            zone: .topRightQuarter,
            label: "TR"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c5X, y: padding, width: qW, height: qH),
            zone: .bottomLeftQuarter,
            label: "BL"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c5X + qW + 3, y: padding, width: qW, height: qH),
            zone: .bottomRightQuarter,
            label: "BR"
        ))

        // 6. Maximizar
        let c6X = c5X + cardWidth + padding
        slots.append(LayoutSlot(
            rect: CGRect(x: c6X, y: padding, width: cardWidth, height: cardHeight),
            zone: .maximize,
            label: "Maximizar"
        ))
    }

    // MARK: - Cartões para Telas Verticais (Portrait)
    private func buildVerticalSlots(cardHeight: CGFloat, padding: CGFloat) {
        let cardCount: CGFloat = 5.0
        let availableWidth = bounds.width - (padding * (cardCount + 1))
        let cardWidth = availableWidth / cardCount

        // 1. Metades Verticais (Topo / Base)
        let c1X = padding
        let halfH = (cardHeight - 3) / 2.0
        slots.append(LayoutSlot(
            rect: CGRect(x: c1X, y: padding + halfH + 3, width: cardWidth, height: halfH),
            zone: .topHalf,
            label: "Topo 1/2"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c1X, y: padding, width: cardWidth, height: halfH),
            zone: .bottomHalf,
            label: "Base 1/2"
        ))

        // 2. Terços Verticais (Topo / Centro / Base)
        let c2X = c1X + cardWidth + padding
        let thirdH = (cardHeight - 4) / 3.0
        slots.append(LayoutSlot(
            rect: CGRect(x: c2X, y: padding + (thirdH * 2) + 4, width: cardWidth, height: thirdH),
            zone: .topThird,
            label: "Topo 1/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c2X, y: padding + thirdH + 2, width: cardWidth, height: thirdH),
            zone: .middleThird,
            label: "Centro 1/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c2X, y: padding, width: cardWidth, height: thirdH),
            zone: .bottomThird,
            label: "Base 1/3"
        ))

        // 3. Dois Terços (2/3 Topo + 1/3 Base)
        let c3X = c2X + cardWidth + padding
        let twoThirdsH = (cardHeight - 3) * (2.0 / 3.0)
        let oneThirdH = (cardHeight - 3) - twoThirdsH
        slots.append(LayoutSlot(
            rect: CGRect(x: c3X, y: padding + oneThirdH + 3, width: cardWidth, height: twoThirdsH),
            zone: .topTwoThirds,
            label: "Topo 2/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c3X, y: padding, width: cardWidth, height: oneThirdH),
            zone: .bottomThird,
            label: "Base 1/3"
        ))

        // 4. Invertido (1/3 Topo + 2/3 Base)
        let c4X = c3X + cardWidth + padding
        slots.append(LayoutSlot(
            rect: CGRect(x: c4X, y: padding + twoThirdsH + 3, width: cardWidth, height: oneThirdH),
            zone: .topThird,
            label: "Topo 1/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: c4X, y: padding, width: cardWidth, height: twoThirdsH),
            zone: .bottomTwoThirds,
            label: "Base 2/3"
        ))

        // 5. Maximizar
        let c5X = c4X + cardWidth + padding
        slots.append(LayoutSlot(
            rect: CGRect(x: c5X, y: padding, width: cardWidth, height: cardHeight),
            zone: .maximize,
            label: "Maximizar"
        ))
    }

    func drawCanvas(in dirtyRect: NSRect) {
        if slots.isEmpty { rebuildSlots() }

        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)

        // 1. Container Apple Glass com borda e lavagem cinza claro translúcida
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        let containerTint = isDark
            ? NSColor(white: 0.12, alpha: 0.45)
            : NSColor(white: 0.96, alpha: 0.65)
        containerTint.setFill()
        bgPath.fill()

        // Borda externa de vidro translúcido
        let containerRim = isDark
            ? NSColor(white: 1.0, alpha: 0.30)
            : NSColor(white: 0.0, alpha: 0.18)
        containerRim.setStroke()
        bgPath.lineWidth = 1.0
        bgPath.stroke()

        // 2. Desenho de cada slot com acabamento translúcido cinza claro (Apple Glass)
        for slot in slots {
            let isHovered = (slot.zone == hoveredZone)
            let slotPath = NSBezierPath(roundedRect: slot.rect, xRadius: 6, yRadius: 6)

            if isHovered {
                // Estado Hover: Vidro translúcido cinza claro iluminado (Apple Glass)
                let hoverFill = isDark
                    ? NSColor(white: 1.0, alpha: 0.38)
                    : NSColor(white: 0.85, alpha: 0.55)
                hoverFill.setFill()
                slotPath.fill()

                // Borda especular de alto contraste
                let hoverStroke = isDark
                    ? NSColor.white
                    : NSColor(white: 0.10, alpha: 0.90)
                hoverStroke.setStroke()
                slotPath.lineWidth = 2.0
                slotPath.stroke()

                // Brilho especular interno no slot
                let innerSlotRect = slot.rect.insetBy(dx: 1.0, dy: 1.0)
                if innerSlotRect.width > 0 && innerSlotRect.height > 0 {
                    let innerSlotPath = NSBezierPath(roundedRect: innerSlotRect, xRadius: 5, yRadius: 5)
                    let innerGlow = isDark
                        ? NSColor(white: 1.0, alpha: 0.30)
                        : NSColor(white: 1.0, alpha: 0.65)
                    innerGlow.setStroke()
                    innerSlotPath.lineWidth = 0.8
                    innerSlotPath.stroke()
                }
            } else {
                // Estado Normal: Placa sutil translúcida cinza claro bem visível
                let normalFill = isDark
                    ? NSColor(white: 1.0, alpha: 0.10)
                    : NSColor(white: 0.0, alpha: 0.06)
                normalFill.setFill()
                slotPath.fill()

                let normalStroke = isDark
                    ? NSColor(white: 1.0, alpha: 0.25)
                    : NSColor(white: 0.0, alpha: 0.20)
                normalStroke.setStroke()
                slotPath.lineWidth = 1.0
                slotPath.stroke()
            }

            // Tipografia nítida e refinada
            let textColor: NSColor
            if isHovered {
                textColor = isDark ? NSColor.white : NSColor.black
            } else {
                textColor = isDark ? NSColor(white: 0.92, alpha: 0.90) : NSColor(white: 0.15, alpha: 0.85)
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: isHovered ? .bold : .semibold),
                .foregroundColor: textColor
            ]
            let str = NSAttributedString(string: slot.label, attributes: attributes)
            let textSize = str.size()
            let textRect = CGRect(
                x: slot.rect.midX - (textSize.width / 2.0),
                y: slot.rect.midY - (textSize.height / 2.0),
                width: textSize.width,
                height: textSize.height
            )
            str.draw(in: textRect)
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
