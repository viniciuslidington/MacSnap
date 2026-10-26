import Cocoa

/// Janela flutuante que atua como a barra divisória interativa entre duas janelas emparelhadas.
/// Permite arrastar o divisor para redimensionar ambas as janelas simultaneamente.
@MainActor
public final class DividerHandleWindow: NSPanel {
    public var onDividerDragged: ((CGFloat) -> Void)?
    public var onDividerReleased: (() -> Void)?

    private let handleWidth: CGFloat = 16.0
    private var isDragging = false

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
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = DividerCustomView()
        view.dividerWindow = self
        self.contentView = view
    }

    /// Posiciona o divisor sobre a linha que separa as duas janelas.
    public func updatePosition(dividerX: CGFloat, visibleFrame: CGRect) {
        let frame = CGRect(
            x: dividerX - (handleWidth / 2.0),
            y: visibleFrame.origin.y,
            width: handleWidth,
            height: visibleFrame.height
        )
        self.setFrame(frame, display: true)
        if !self.isVisible {
            self.orderFrontRegardless()
        }
    }
}

/// View responsável pelo desenho do separador e captura de arraste do mouse.
final class DividerCustomView: NSView {
    weak var dividerWindow: DividerHandleWindow?
    private let pillWidth: CGFloat = 4.0
    private let pillHeight: CGFloat = 48.0
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
    }

    override func resetCursorRects() {
        // Cursor de redimensionamento horizontal estilo Windows (⬌)
        self.addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let mouseLoc = NSEvent.mouseLocation
        dividerWindow?.onDividerDragged?(mouseLoc.x)
    }

    override func mouseUp(with event: NSEvent) {
        dividerWindow?.onDividerReleased?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Desenha a "pílula" central cinza sutil indicando a área de pega
        let pillRect = NSRect(
            x: (bounds.width - pillWidth) / 2.0,
            y: (bounds.height - pillHeight) / 2.0,
            width: pillWidth,
            height: pillHeight
        )

        let path = NSBezierPath(roundedRect: pillRect, xRadius: 2.0, yRadius: 2.0)
        let color = isHovered ? NSColor.controlAccentColor : NSColor.secondaryLabelColor.withAlphaComponent(0.6)
        color.setFill()
        path.fill()
    }
}
