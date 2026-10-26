import Cocoa

/// Floating panel that serves as the interactive resize divider between two paired windows.
/// Supports vertical orientation (⬌) for side-by-side windows and horizontal (⬍) for stacked windows on portrait displays.
@MainActor
public final class DividerHandleWindow: NSPanel {
    public var onDividerDragStarted: (() -> Void)?
    public var onDividerDragged: ((CGFloat) -> Void)?
    public var onDividerReleased: (() -> Void)?
    public var validatePair: (() -> Bool)?
    public var onInvalidPairDetected: (() -> Void)?
    public var isOccludedAtPoint: ((CGPoint) -> Bool)?

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
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        customView.dividerWindow = self
        self.contentView = customView
    }

    /// Indicates whether the user is actively dragging this divider.
    public var isDragging: Bool {
        customView.isDragging
    }

    public override func orderOut(_ sender: Any?) {
        customView.alphaValue = 0.0
        customView.isDragging = false
        super.orderOut(sender)
    }

    /// Immediately suppresses visibility and interactions without destroying pairing state.
    public func hideDividerImmediately() {
        customView.hideImmediately()
    }

    /// Updates the divider based on a `PairedSplit` instance.
    public func update(for pair: PairedSplit) {
        customView.orientation = pair.orientation
        self.setFrame(pair.dividerFrame, display: true)
        customView.needsDisplay = true
        if !self.isVisible {
            self.orderFrontRegardless()
        }
    }

    /// Legacy method for horizontal compatibility.
    public func updatePosition(dividerX: CGFloat, visibleFrame: CGRect) {
        let handleWidth: CGFloat = 24.0
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

/// View responsible for rendering the separator and capturing mouse drag events.
final class DividerCustomView: NSView {
    weak var dividerWindow: DividerHandleWindow?
    var orientation: SplitOrientation = .horizontal {
        didSet {
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    private var isHovered = false
    var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        alphaValue = 0.0 // Hidden by default to keep the desktop clean
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

    func hideImmediately() {
        isHovered = false
        alphaValue = 0.0
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // Allows the first click to be immediately captured only when unoccluded
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let screenPoint = window?.convertPoint(toScreen: point) ?? NSEvent.mouseLocation
        if let isOccluded = dividerWindow?.isOccludedAtPoint, isOccluded(screenPoint) {
            return nil
        }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        let mouseLocation = NSEvent.mouseLocation
        if let isOccluded = dividerWindow?.isOccludedAtPoint, isOccluded(mouseLocation) {
            self.discardCursorRects()
            return
        }
        let cursor: NSCursor = (orientation == .horizontal) ? .resizeLeftRight : .resizeUpDown
        self.addCursorRect(bounds, cursor: cursor)
    }

    override func mouseEntered(with event: NSEvent) {
        if let validator = dividerWindow?.validatePair {
            guard validator() else {
                dividerWindow?.orderOut(nil)
                dividerWindow?.onInvalidPairDetected?()
                return
            }
        }

        let mouseLocation = NSEvent.mouseLocation
        if let isOccluded = dividerWindow?.isOccludedAtPoint, isOccluded(mouseLocation) {
            self.alphaValue = 0.0
            isHovered = false
            needsDisplay = true
            return
        }

        isHovered = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let mouseLocation = NSEvent.mouseLocation
        let isOccluded = dividerWindow?.isOccludedAtPoint?(mouseLocation) ?? false

        if isOccluded {
            if isHovered || alphaValue > 0.01 {
                isHovered = false
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    self.animator().alphaValue = 0.0
                }
                window?.invalidateCursorRects(for: self)
            }
        } else {
            if !isHovered && !isDragging {
                isHovered = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().alphaValue = 1.0
                }
                window?.invalidateCursorRects(for: self)
            }
        }
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

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        self.alphaValue = 1.0
        needsDisplay = true
        dividerWindow?.onDividerDragStarted?()
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

        // 1. Translucent glass divider line along the window intersection
        let activeLineColor = isDark
            ? NSColor(white: 1.0, alpha: 0.75)
            : NSColor(white: 0.25, alpha: 0.65)

        // Inset so the divider line stops before the window corner radiuses curve away
        let cornerInset: CGFloat = 20.0

        if orientation == .horizontal {
            let lineX = bounds.midX
            let linePath = NSBezierPath()
            let startY = cornerInset
            let endY = max(cornerInset, bounds.height - cornerInset)
            linePath.move(to: CGPoint(x: lineX, y: startY))
            linePath.line(to: CGPoint(x: lineX, y: endY))
            linePath.lineWidth = 1.5
            linePath.lineCapStyle = .round
            activeLineColor.setStroke()
            linePath.stroke()
        } else {
            let lineY = bounds.midY
            let linePath = NSBezierPath()
            let startX = cornerInset
            let endX = max(cornerInset, bounds.width - cornerInset)
            linePath.move(to: CGPoint(x: startX, y: lineY))
            linePath.line(to: CGPoint(x: endX, y: lineY))
            linePath.lineWidth = 1.5
            linePath.lineCapStyle = .round
            activeLineColor.setStroke()
            linePath.stroke()
        }

        // 2. Central Apple Glass pill handle
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

        // Subtle glass stroke on pill handle
        let pillStrokeColor = isDark ? NSColor(white: 1.0, alpha: 0.40) : NSColor(white: 0.0, alpha: 0.20)
        pillStrokeColor.setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }
}
