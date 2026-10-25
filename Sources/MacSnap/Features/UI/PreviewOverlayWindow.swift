import Cocoa
import QuartzCore

/// Janela de sobreposição translúcida que renderiza a área para onde a janela irá ao ser solta,
/// idêntico ao indicador de Snap do Windows.
@MainActor
public final class PreviewOverlayWindow: NSWindow {
    private let visualEffectView = NSVisualEffectView()
    private let borderBox = NSBox()

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        setupView()
    }

    private func setupView() {
        guard let contentView = self.contentView else { return }

        // Efeito translúcido (frosted glass)
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 14
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(visualEffectView)

        // Borda de destaque azul/sistema com opacidade
        borderBox.boxType = .custom
        borderBox.borderWidth = 2.5
        borderBox.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85)
        borderBox.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.20)
        borderBox.cornerRadius = 14
        borderBox.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(borderBox)

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),

            borderBox.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            borderBox.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            borderBox.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            borderBox.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])
    }

    /// Exibe ou anima a janela de pré-visualização para o frame desejado.
    public func present(at targetRect: CGRect, animated: Bool = true) {
        if !self.isVisible {
            self.setFrame(targetRect, display: true)
            self.alphaValue = 0.0
            self.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
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
