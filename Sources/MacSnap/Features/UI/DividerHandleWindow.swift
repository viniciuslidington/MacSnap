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
        wantsLayer = true
        alphaValue = 0.0 // Oculto por padrão para não poluir a tela
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        alphaValue = 0.0
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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0.0
            }
        }
        needsDisplay = true
    }

    // CRUCIAL: Inicia o rastreamento de arraste do mouse
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        self.alphaValue = 1.0
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let mouseLoc = NSEvent.mouseLocation
        let coordinate: CGFloat = (orientation == .horizontal) ? mouseLoc.x : mouseLoc.y
        dividerWindow?.onDividerDragged?(coordinate)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        let mouseLocation = NSEvent.mouseLocation
        let windowLoc = window?.convertPoint(fromScreen: mouseLocation) ?? .zero
        let localLoc = convert(windowLoc, from: nil)

        if bounds.contains(localLoc) {
            isHovered = true
            self.alphaValue = 1.0
        } else {
            isHovered = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0.0
            }
        }
        needsDisplay = true
        dividerWindow?.onDividerReleased?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isActive = isHovered || isDragging
        guard isActive || alphaValue > 0.01 else { return }

        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)

        // 1. Linha divisória de vidro translúcido ao longo da intercessão
        let activeLineColor = isDark
            ? NSColor(white: 1.0, alpha: 0.75)
            : NSColor(white: 0.25, alpha: 0.65)

        if orientation == .horizontal {
            let lineX = bounds.midX
            let linePath = NSBezierPath()
            linePath.move(to: CGPoint(x: lineX, y: 0))
            linePath.line(to: CGPoint(x: lineX, y: bounds.height))
            linePath.lineWidth = 1.5
            activeLineColor.setStroke()
            linePath.stroke()
        } else {
            let lineY = bounds.midY
            let linePath = NSBezierPath()
            linePath.move(to: CGPoint(x: 0, y: lineY))
            linePath.line(to: CGPoint(x: bounds.width, y: lineY))
            linePath.lineWidth = 1.5
            activeLineColor.setStroke()
            linePath.stroke()
        }

        // 2. Pílula central de vidro translúcido (Apple Glass Handle)
        let pillRect: NSRect
        if orientation == .horizontal {
            let pillWidth: CGFloat = 6.0
            let pillHeight: CGFloat = 56.0
            pillRect = NSRect(
                x: (bounds.width - pillWidth) / 2.0,
                y: (bounds.height - pillHeight) / 2.0,
                width: pillWidth,
                height: pillHeight
            )
        } else {
            let pillWidth: CGFloat = 56.0
            let pillHeight: CGFloat = 6.0
            pillRect = NSRect(
                x: (bounds.width - pillWidth) / 2.0,
                y: (bounds.height - pillHeight) / 2.0,
                width: pillWidth,
                height: pillHeight
            )
        }

        let path = NSBezierPath(roundedRect: pillRect, xRadius: 3.0, yRadius: 3.0)
        let pillFillColor: NSColor
        if isDragging {
            pillFillColor = isDark ? NSColor(white: 1.0, alpha: 0.95) : NSColor(white: 0.15, alpha: 0.95)
        } else {
            pillFillColor = isDark ? NSColor(white: 1.0, alpha: 0.85) : NSColor(white: 0.25, alpha: 0.85)
        }
        pillFillColor.setFill()
        path.fill()

        // Borda sutil de vidro na pílula
        let pillStrokeColor = isDark ? NSColor(white: 1.0, alpha: 0.40) : NSColor(white: 0.0, alpha: 0.20)
        pillStrokeColor.setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }
}
