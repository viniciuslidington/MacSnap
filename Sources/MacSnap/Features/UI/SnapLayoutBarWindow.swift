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

/// View com o desenho visual translúcido dos cards de layout horizontal e vertical.
final class SnapLayoutBarView: NSView {
    private struct LayoutSlot {
        let rect: CGRect
        let zone: SnapZone
        let label: String
    }

    var isPortrait: Bool = false {
        didSet {
            rebuildSlots()
            needsDisplay = true
        }
    }

    private var slots: [LayoutSlot] = []
    private var hoveredZone: SnapZone?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func resetHover() {
        hoveredZone = nil
        needsDisplay = true
    }

    func updateHover(at point: CGPoint) -> SnapZone? {
        for slot in slots {
            if slot.rect.contains(point) {
                if hoveredZone != slot.zone {
                    hoveredZone = slot.zone
                    needsDisplay = true
                }
                return slot.zone
            }
        }

        if hoveredZone != nil {
            hoveredZone = nil
            needsDisplay = true
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if slots.isEmpty { rebuildSlots() }

        // Fundo translúcido
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        bgPath.fill()

        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        bgPath.lineWidth = 1.0
        bgPath.stroke()

        // Desenha cada slot com estado normal ou destacado
        for slot in slots {
            let isHovered = (slot.zone == hoveredZone)
            let slotPath = NSBezierPath(roundedRect: slot.rect, xRadius: 5, yRadius: 5)

            if isHovered {
                NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
                slotPath.fill()
                NSColor.controlAccentColor.setStroke()
                slotPath.lineWidth = 2.0
                slotPath.stroke()
            } else {
                NSColor.controlColor.withAlphaComponent(0.6).setFill()
                slotPath.fill()
                NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
                slotPath.lineWidth = 1.0
                slotPath.stroke()
            }

            // Texto do slot
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: isHovered ? .bold : .medium),
                .foregroundColor: isHovered ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
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
