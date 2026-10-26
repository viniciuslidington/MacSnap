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
        let handleWidth: CGFloat = 16.0
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
        // Cursor de acordo com a direção do divisor:
        // Horizontal (janelas lado a lado) -> ⬌ (resizeLeftRight)
        // Vertical (janelas empilhadas no monitor vertical) -> ⬍ (resizeUpDown)
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

    override func mouseDragged(with event: NSEvent) {
        let mouseLoc = NSEvent.mouseLocation
        let coordinate: CGFloat = (orientation == .horizontal) ? mouseLoc.x : mouseLoc.y
        dividerWindow?.onDividerDragged?(coordinate)
    }

    override func mouseUp(with event: NSEvent) {
        dividerWindow?.onDividerReleased?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pillRect: NSRect
        if orientation == .horizontal {
            // Pílula vertical estreita
            let pillWidth: CGFloat = 4.0
            let pillHeight: CGFloat = 48.0
            pillRect = NSRect(
                x: (bounds.width - pillWidth) / 2.0,
                y: (bounds.height - pillHeight) / 2.0,
                width: pillWidth,
                height: pillHeight
            )
        } else {
            // Pílula horizontal larga
            let pillWidth: CGFloat = 48.0
            let pillHeight: CGFloat = 4.0
            pillRect = NSRect(
                x: (bounds.width - pillWidth) / 2.0,
                y: (bounds.height - pillHeight) / 2.0,
                width: pillWidth,
                height: pillHeight
            )
        }

        let path = NSBezierPath(roundedRect: pillRect, xRadius: 2.0, yRadius: 2.0)
        let color = isHovered ? NSColor.controlAccentColor : NSColor.secondaryLabelColor.withAlphaComponent(0.65)
        color.setFill()
        path.fill()
    }
}
