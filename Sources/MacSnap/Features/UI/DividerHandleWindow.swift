import Cocoa

/// Janela flutuante que atua como a barra divisória interativa entre duas janelas emparelhadas.
/// Suporta orientação vertical (⬌) para janelas lado a lado e horizontal (⬍) para janelas empilhadas no monitor vertical.
@MainActor
public final class DividerHandleWindow: NSPanel {
    public var onDividerDragged: ((CGFloat) -> Void)?
    public var onDividerReleased: (() -> Void)?

    private let customView: DividerCustomView

    public init() {
        self.customView = DividerCustomView()
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

        customView.dividerWindow = self
        self.contentView = customView
    }

    /// Atualiza o divisor com base no objeto `PairedSplit`.
    public func update(for pair: PairedSplit) {
        customView.orientation = pair.orientation
        self.setFrame(pair.dividerFrame, display: true)
        if !self.isVisible {
            self.orderFrontRegardless()
        }
    }

    /// Método legado para compatibilidade horizontal.
    public func updatePosition(dividerX: CGFloat, visibleFrame: CGRect) {
        let handleWidth: CGFloat = 20.0
        let frame = CGRect(
            x: dividerX - (handleWidth / 2.0),
            y: visibleFrame.origin.y,
            width: handleWidth,
            height: visibleFrame.height
        )
        customView.orientation = .horizontal
        self.setFrame(frame, display: true)
        if !self.isVisible {
            self.orderFrontRegardless()
        }
    }
}

/// View responsável pelo desenho do separador e captura de arraste do mouse.
final class DividerCustomView: NSView {
    weak var dividerWindow: DividerHandleWindow?
    var orientation: SplitOrientation = .horizontal {
        didSet {
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    private var isHovered = false
    private var isDragging = false

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

    // CRUCIAL: Permite que o primeiro clique seja imediatamente capturado mesmo com outros apps em foco
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func resetCursorRects() {
        let cursor: NSCursor = (orientation == .horizontal) ? .resizeLeftRight : .resizeUpDown
        self.addCursorRect(bounds, cursor: cursor)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    // CRUCIAL: Inicia o rastreamento de arraste do mouse
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let mouseLoc = NSEvent.mouseLocation
        let coordinate: CGFloat = (orientation == .horizontal) ? mouseLoc.x : mouseLoc.y
        dividerWindow?.onDividerDragged?(coordinate)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
        dividerWindow?.onDividerReleased?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isActive = isHovered || isDragging
        let accentColor = NSColor.controlAccentColor
        let baseLineColor = NSColor.separatorColor.withAlphaComponent(0.4)

        // 1. Linha divisória fina sutil ao longo de toda a extensão da intercessão
        if orientation == .horizontal {
            let lineX = bounds.midX
            let linePath = NSBezierPath()
            linePath.move(to: CGPoint(x: lineX, y: 0))
            linePath.line(to: CGPoint(x: lineX, y: bounds.height))
            linePath.lineWidth = isActive ? 2.0 : 1.0
            (isActive ? accentColor.withAlphaComponent(0.85) : baseLineColor).setStroke()
            linePath.stroke()
        } else {
            let lineY = bounds.midY
            let linePath = NSBezierPath()
            linePath.move(to: CGPoint(x: 0, y: lineY))
            linePath.line(to: CGPoint(x: bounds.width, y: lineY))
            linePath.lineWidth = isActive ? 2.0 : 1.0
            (isActive ? accentColor.withAlphaComponent(0.85) : baseLineColor).setStroke()
            linePath.stroke()
        }

        // 2. Pílula central em destaque para indicar o ponto de pega
        let pillRect: NSRect
        if orientation == .horizontal {
            let pillWidth: CGFloat = isActive ? 6.0 : 4.0
            let pillHeight: CGFloat = isActive ? 56.0 : 44.0
            pillRect = NSRect(
                x: (bounds.width - pillWidth) / 2.0,
                y: (bounds.height - pillHeight) / 2.0,
                width: pillWidth,
                height: pillHeight
            )
        } else {
            let pillWidth: CGFloat = isActive ? 56.0 : 44.0
            let pillHeight: CGFloat = isActive ? 6.0 : 4.0
            pillRect = NSRect(
                x: (bounds.width - pillWidth) / 2.0,
                y: (bounds.height - pillHeight) / 2.0,
                width: pillWidth,
                height: pillHeight
            )
        }

        let path = NSBezierPath(roundedRect: pillRect, xRadius: 3.0, yRadius: 3.0)
        let pillColor = isDragging ? accentColor : (isHovered ? accentColor.withAlphaComponent(0.9) : NSColor.secondaryLabelColor.withAlphaComponent(0.7))
        pillColor.setFill()
        path.fill()
    }
}
