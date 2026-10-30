import Cocoa
import QuartzCore

/// Translucent overlay window that renders the snap target zone where a window will dock upon release.
/// Features uniform 4-sided rendering and an elevated window level (`.screenSaver - 5`)
/// to guarantee clear visibility even over frontmost windows with drop shadows.
@MainActor
public final class PreviewOverlayWindow: NSWindow {
    private let previewView = PreviewContentView()
    private var currentTargetRect: CGRect?
    private var presentationGeneration: UInt64 = 0

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        // Below SnapLayoutBarWindow so layout cards remain on top of the preview
        self.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 5)
        self.ignoresMouseEvents = true
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        self.contentView = previewView
    }

    /// Displays or animates the preview overlay to the specified frame.
    public func present(at targetRect: CGRect, animated: Bool = true) {
        // Avoid repeated re-animation when cursor moves while maintaining the same snap zone
        if self.isVisible && self.currentTargetRect == targetRect {
            return
        }
        presentationGeneration &+= 1
        self.currentTargetRect = targetRect

        if !self.isVisible {
            self.setFrame(targetRect, display: true)
            self.alphaValue = 0.0
            // orderFrontRegardless ensures the window is visible even with another app focused
            self.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 0.92
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? 0.12 : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                // Crossing a gap can start dismiss() immediately before this selection.
                // Supersede its fade as well as its stale completion callback.
                self.animator().alphaValue = 0.92
                self.animator().setFrame(targetRect, display: true)
            }
        }
    }

    /// Hides the preview window with a smooth fade-out.
    public func dismiss() {
        guard self.isVisible, currentTargetRect != nil else { return }
        self.currentTargetRect = nil
        presentationGeneration &+= 1
        let generation = presentationGeneration

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.presentationGeneration == generation else { return }
                self.orderOut(nil)
            }
        })
    }
}

/// Custom view that renders the preview zone in Apple Glass UI styling,
/// utilizing translucent frosted glass, subtle light-gray depth, and specular edge reflections.
final class PreviewContentView: NSView {
    private let visualEffectView = NSVisualEffectView()
    private let canvasView = PreviewOverlayCanvasView()
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
        visualEffectView.alphaValue = 0.80
        addSubview(visualEffectView)

        canvasView.onDraw = { [weak self] dirtyRect in
            self?.drawGlassOverlay(in: dirtyRect)
        }
        addSubview(canvasView)
    }

    override func layout() {
        super.layout()
        let innerRect = bounds.insetBy(dx: margin, dy: margin)
        visualEffectView.frame = innerRect
        canvasView.frame = bounds
        canvasView.needsDisplay = true
    }

    func drawGlassOverlay(in dirtyRect: NSRect) {
        let innerRect = bounds.insetBy(dx: margin, dy: margin)
        guard innerRect.width > 0 && innerRect.height > 0 else { return }

        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let path = NSBezierPath(roundedRect: innerRect, xRadius: cornerRadius, yRadius: cornerRadius)

        // 1. Light translucent frosted background (Apple Glass UI)
        let glassFillColor = isDark
            ? NSColor(white: 1.0, alpha: 0.06)
            : NSColor(white: 1.0, alpha: 0.10)
        glassFillColor.setFill()
        path.fill()

        // 2. Luminous outer specular rim
        let outerRimColor = isDark
            ? NSColor(white: 1.0, alpha: 0.45)
            : NSColor(white: 0.20, alpha: 0.28)
        outerRimColor.setStroke()
        path.lineWidth = 1.4
        path.stroke()

        // 3. Inner specular light glow for a refined glass finish
        let innerGlowRect = innerRect.insetBy(dx: 1.5, dy: 1.5)
        if innerGlowRect.width > 0 && innerGlowRect.height > 0 {
            let innerPath = NSBezierPath(
                roundedRect: innerGlowRect,
                xRadius: max(0, cornerRadius - 1.5),
                yRadius: max(0, cornerRadius - 1.5)
            )
            let innerGlowColor = isDark
                ? NSColor(white: 1.0, alpha: 0.12)
                : NSColor(white: 1.0, alpha: 0.35)
            innerGlowColor.setStroke()
            innerPath.lineWidth = 0.8
            innerPath.stroke()
        }
    }
}

/// Canvas overlay for drawing the borders and specular glow on top of NSVisualEffectView.
final class PreviewOverlayCanvasView: NSView {
    var onDraw: ((NSRect) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        onDraw?(dirtyRect)
    }
}
