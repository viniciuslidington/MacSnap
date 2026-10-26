import Cocoa
import QuartzCore

/// Barra flutuante de layouts (estilo Snap Bar do Windows 11) que se desdobra
/// no topo da tela quando o usuário arrasta uma janela, oferecendo templates
/// de organização otimizados para monitores verticais e horizontais.
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

    /// Exibe a barra de layouts no topo da tela indicada.
    public func present(on screen: NSScreen) {
        guard !isPresented else { return }
        isPresented = true

        let visible = screen.visibleFrame
        let barWidth: CGFloat = min(visible.width - 40, 480)
        let barHeight: CGFloat = 88

        let x = visible.origin.x + (visible.width - barWidth) / 2.0
        let targetY = visible.origin.y + visible.height - barHeight - 8
        let startY = visible.origin.y + visible.height + 20 // começa acima para deslizar

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

    /// Esconde a barra com animação.
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

/// View com o desenho visual translúcido dos cards de layout vertical (1/2, 1/3, 2/3 e Maximizar).
final class SnapLayoutBarView: NSView {
    private struct LayoutSlot {
        let rect: CGRect
        let zone: SnapZone
        let label: String
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

    private func rebuildSlots() {
        slots.removeAll()
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }

        let padding: CGFloat = 10.0
        let availableWidth = b.width - (padding * 5)
        let cardWidth = availableWidth / 4.0
        let cardHeight = b.height - (padding * 2)

        // Card 1: Metades Verticais (Topo / Base)
        let card1X = padding
        let halfHeight = (cardHeight - 4) / 2.0
        slots.append(LayoutSlot(
            rect: CGRect(x: card1X, y: padding + halfHeight + 4, width: cardWidth, height: halfHeight),
            zone: .topHalf,
            label: "Topo 1/2"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: card1X, y: padding, width: cardWidth, height: halfHeight),
            zone: .bottomHalf,
            label: "Base 1/2"
        ))

        // Card 2: Terços Verticais (Topo / Centro / Base)
        let card2X = card1X + cardWidth + padding
        let thirdH = (cardHeight - 6) / 3.0
        slots.append(LayoutSlot(
            rect: CGRect(x: card2X, y: padding + (thirdH * 2) + 6, width: cardWidth, height: thirdH),
            zone: .topThird,
            label: "Topo 1/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: card2X, y: padding + thirdH + 3, width: cardWidth, height: thirdH),
            zone: .middleThird,
            label: "Centro 1/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: card2X, y: padding, width: cardWidth, height: thirdH),
            zone: .bottomThird,
            label: "Base 1/3"
        ))

        // Card 3: Dois Terços (2/3 Topo + 1/3 Base)
        let card3X = card2X + cardWidth + padding
        let twoThirdsH = (cardHeight - 4) * (2.0 / 3.0)
        let oneThirdH = (cardHeight - 4) - twoThirdsH
        slots.append(LayoutSlot(
            rect: CGRect(x: card3X, y: padding + oneThirdH + 4, width: cardWidth, height: twoThirdsH),
            zone: .topTwoThirds,
            label: "Topo 2/3"
        ))
        slots.append(LayoutSlot(
            rect: CGRect(x: card3X, y: padding, width: cardWidth, height: oneThirdH),
            zone: .bottomThird,
            label: "Base 1/3"
        ))

        // Card 4: Maximizar
        let card4X = card3X + cardWidth + padding
        slots.append(LayoutSlot(
            rect: CGRect(x: card4X, y: padding, width: cardWidth, height: cardHeight),
            zone: .maximize,
            label: "Maximizar"
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if slots.isEmpty { rebuildSlots() }

        // Fundo estilo vidro fosco
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        bgPath.fill()

        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        bgPath.lineWidth = 1.0
        bgPath.stroke()

        // Desenha cada slot com estado normal ou destacado
        for slot in slots {
            let isHovered = (slot.zone == hoveredZone)
            let slotPath = NSBezierPath(roundedRect: slot.rect, xRadius: 6, yRadius: 6)

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
                .font: NSFont.systemFont(ofSize: 10, weight: isHovered ? .bold : .medium),
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
