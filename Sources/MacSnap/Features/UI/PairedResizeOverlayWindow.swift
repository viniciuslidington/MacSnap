import Cocoa
import QuartzCore

/// Floating translucent overlay window that covers both windows during paired resizing,
/// displaying an Apple Glass frosted blur effect over each window in real time.
/// Renders at `screenSaver - 2` level, sitting directly beneath the interactive divider handle.
@MainActor
public final class PairedResizeOverlayWindow: NSPanel {
    private let overlayContentView = PairedResizeOverlayContentView()
    public private(set) var currentScreen: NSScreen?
    public private(set) var isPresenting: Bool = false

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        // Positioned just below DividerHandleWindow (.screenSaver) so the divider handle remains on top
        self.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 2)
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        self.contentView = overlayContentView
    }

    /// Returns the local frame of the first blur panel (for testing and inspection).
    public var firstPanelFrame: CGRect {
        overlayContentView.firstPanel.frame
    }

    /// Returns the local frame of the second blur panel (for testing and inspection).
    public var secondPanelFrame: CGRect {
        overlayContentView.secondPanel.frame
    }

    /// Presents the dual blur overlay covering the two windows being resized.
    public func present(on screen: NSScreen, firstRect: CGRect, secondRect: CGRect, animated: Bool = true) {
        currentScreen = screen
        isPresenting = true

        self.setFrame(screen.frame, display: true)

        let localFirst = localRect(for: firstRect, on: screen)
        let localSecond = localRect(for: secondRect, on: screen)
        overlayContentView.update(firstRect: localFirst, secondRect: localSecond)

        if animated {
            self.alphaValue = 0.0
            self.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 0.92
            }
        } else {
            self.alphaValue = 0.92
            self.orderFrontRegardless()
        }
    }

    /// Updates the blur panel frames synchronously during cursor drag.
    public func update(firstRect: CGRect, secondRect: CGRect) {
        guard let screen = currentScreen else { return }
        let localFirst = localRect(for: firstRect, on: screen)
        let localSecond = localRect(for: secondRect, on: screen)
        overlayContentView.update(firstRect: localFirst, secondRect: localSecond)
    }

    /// Dismisses the dual blur overlay with a smooth fade-out.
    public func dismiss(animated: Bool = true) {
        guard isPresenting else { return }
        isPresenting = false
        currentScreen = nil

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, !self.isPresenting else { return }
                    self.orderOut(nil)
                }
            })
        } else {
            self.alphaValue = 0.0
            self.orderOut(nil)
        }
    }

    private func localRect(for screenRect: CGRect, on screen: NSScreen) -> CGRect {
        CGRect(
            x: screenRect.origin.x - screen.frame.origin.x,
            y: screenRect.origin.y - screen.frame.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )
    }
}

/// Content view containing the two paired blur panels.
final class PairedResizeOverlayContentView: NSView {
    let firstPanel = PairedBlurPanel()
    let secondPanel = PairedBlurPanel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(firstPanel)
        addSubview(secondPanel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        addSubview(firstPanel)
        addSubview(secondPanel)
    }

    func update(firstRect: CGRect, secondRect: CGRect) {
        let margin: CGFloat = 4.0
        let insetFirst = firstRect.insetBy(dx: margin, dy: margin)
        let insetSecond = secondRect.insetBy(dx: margin, dy: margin)

        firstPanel.frame = (insetFirst.width > 0 && insetFirst.height > 0) ? insetFirst : .zero
        secondPanel.frame = (insetSecond.width > 0 && insetSecond.height > 0) ? insetSecond : .zero

        firstPanel.needsDisplay = true
        secondPanel.needsDisplay = true
    }
}

/// Individual Apple Glass blur panel with visual effect backing and specular highlight.
final class PairedBlurPanel: NSView {
    private let visualEffectView = NSVisualEffectView()
    private let canvasView = PairedBlurCanvasView()
    private let cornerRadius: CGFloat = 14.0

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
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true

        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.alphaValue = 0.85
        addSubview(visualEffectView)

        canvasView.onDraw = { [weak self] rect in
            self?.drawOverlay(in: rect)
        }
        addSubview(canvasView)
    }

    override func layout() {
        super.layout()
        visualEffectView.frame = bounds
        canvasView.frame = bounds
        layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.cornerRadius = cornerRadius
    }

    private func drawOverlay(in dirtyRect: NSRect) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)

        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

        // Subtle translucent fill adding body to the blur
        let tint = isDark
            ? NSColor(white: 0.12, alpha: 0.30)
            : NSColor(white: 1.0, alpha: 0.40)
        tint.setFill()
        bgPath.fill()

        // Luminous high-definition outer rim
        let rimColor = isDark
            ? NSColor(white: 1.0, alpha: 0.22)
            : NSColor(white: 0.10, alpha: 0.16)
        rimColor.setStroke()
        bgPath.lineWidth = 1.0
        bgPath.stroke()

        // Top specular reflection line
        if bounds.height > 20 && bounds.width > 32 {
            let topHighlightPath = NSBezierPath()
            let highlightY = bounds.maxY - 1.5
            topHighlightPath.move(to: CGPoint(x: bounds.minX + 16, y: highlightY))
            topHighlightPath.line(to: CGPoint(x: bounds.maxX - 16, y: highlightY))
            let highlightColor = isDark
                ? NSColor(white: 1.0, alpha: 0.35)
                : NSColor(white: 1.0, alpha: 0.65)
            highlightColor.setStroke()
            topHighlightPath.lineWidth = 1.0
            topHighlightPath.stroke()
        }
    }
}

/// Canvas overlay for custom drawing on top of NSVisualEffectView.
final class PairedBlurCanvasView: NSView {
    var onDraw: ((NSRect) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        onDraw?(dirtyRect)
    }
}
