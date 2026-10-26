import Cocoa
import QuartzCore

/// Janela de sobreposição translúcida que renderiza a área para onde a janela irá ao ser solta,
/// com desenho uniforme em todos os 4 lados e nível de exibição superior (`.screenSaver`)
/// para garantir visibilidade perfeita mesmo sobre janelas em foco com sombras.
@MainActor
public final class PreviewOverlayWindow: NSWindow {
    private let previewView = PreviewContentView()
    private var currentTargetRect: CGRect?

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        // Nível .screenSaver garante que a prévia fique sempre à frente de qualquer janela focada
        self.level = .screenSaver
        self.ignoresMouseEvents = true
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        self.contentView = previewView
    }

    /// Exibe ou anima a janela de pré-visualização para o frame desejado.
    public func present(at targetRect: CGRect, animated: Bool = true) {
        // Evita reanimar repetidamente quando o cursor se move mantendo a mesma zona de snap
        if self.isVisible && self.currentTargetRect == targetRect {
            return
        }
        self.currentTargetRect = targetRect

        if !self.isVisible {
            self.setFrame(targetRect, display: true)
            self.alphaValue = 0.0
            // orderFrontRegardless garante que a janela suba mesmo com outro app em primeiro plano
            self.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1.0
            }
        } else {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().setFrame(targetRect, display: true)
                }
            } else {
                self.setFrame(targetRect, display: true)
            }
        }
    }

    /// Esconde a janela de pré-visualização com fade-out.
    public func dismiss() {
        guard self.isVisible else { return }
        self.currentTargetRect = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.orderOut(nil)
            }
        })
    }
}

/// View personalizada que renderiza a área de pré-visualização no estilo Apple Glass UI,
/// utilizando vidro fosco translúcido, tom cinza claro e reflexos especulares nas bordas.
final class PreviewContentView: NSView {
    private let visualEffectView = NSVisualEffectView()
    private let margin: CGFloat = 8.0
    private let cornerRadius: CGFloat = 16.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupEffect()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupEffect()
    }

    private func setupEffect() {
        wantsLayer = true

        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.masksToBounds = true
        addSubview(visualEffectView)
    }

    override func layout() {
        super.layout()
        let innerRect = bounds.insetBy(dx: margin, dy: margin)
        visualEffectView.frame = innerRect
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let innerRect = bounds.insetBy(dx: margin, dy: margin)
        guard innerRect.width > 0 && innerRect.height > 0 else { return }

        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let path = NSBezierPath(roundedRect: innerRect, xRadius: cornerRadius, yRadius: cornerRadius)

        // 1. Fundo translúcido cinza claro (Apple Glass UI)
        let glassFillColor = isDark
            ? NSColor(white: 0.95, alpha: 0.16)
            : NSColor(white: 0.70, alpha: 0.22)
        glassFillColor.setFill()
        path.fill()

        // 2. Borda externa luminosa de vidro lapidado (Specular Rim)
        let outerRimColor = isDark
            ? NSColor(white: 1.0, alpha: 0.60)
            : NSColor(white: 0.30, alpha: 0.40)
        outerRimColor.setStroke()
        path.lineWidth = 1.8
        path.stroke()

        // 3. Reflexo interno de luz para acabamento refinado de vidro (Inner Specular Glow)
        let innerGlowRect = innerRect.insetBy(dx: 1.5, dy: 1.5)
        if innerGlowRect.width > 0 && innerGlowRect.height > 0 {
            let innerPath = NSBezierPath(
                roundedRect: innerGlowRect,
                xRadius: max(0, cornerRadius - 1.5),
                yRadius: max(0, cornerRadius - 1.5)
            )
            let innerGlowColor = isDark
                ? NSColor(white: 1.0, alpha: 0.20)
                : NSColor(white: 1.0, alpha: 0.50)
            innerGlowColor.setStroke()
            innerPath.lineWidth = 1.0
            innerPath.stroke()
        }
    }
}
