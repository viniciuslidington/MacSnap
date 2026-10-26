import Cocoa
import QuartzCore

/// Floating translucent overlay window that covers both windows during paired resizing,
/// displaying an Apple Glass frosted blur effect with centered application logos.
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

    /// Presents the dual frosted glass overlay with application logos covering the two windows being resized.
    public func present(
        on screen: NSScreen,
        firstRect: CGRect,
        secondRect: CGRect,
        firstAppIcon: NSImage? = nil,
        secondAppIcon: NSImage? = nil,
        firstAppName: String? = nil,
        secondAppName: String? = nil,
        animated: Bool = true
    ) {
        currentScreen = screen
        isPresenting = true

        self.setFrame(screen.frame, display: true)

        overlayContentView.configure(
            firstAppIcon: firstAppIcon,
            secondAppIcon: secondAppIcon,
            firstAppName: firstAppName,
            secondAppName: secondAppName
        )

        let localFirst = localRect(for: firstRect, on: screen)
        let localSecond = localRect(for: secondRect, on: screen)
        overlayContentView.update(firstRect: localFirst, secondRect: localSecond)

        if animated {
            self.alphaValue = 0.0
            self.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 0.94
            }
        } else {
            self.alphaValue = 0.94
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

    func configure(
        firstAppIcon: NSImage?,
        secondAppIcon: NSImage?,
        firstAppName: String?,
        secondAppName: String?
    ) {
        firstPanel.configure(appIcon: firstAppIcon, appName: firstAppName)
        secondPanel.configure(appIcon: secondAppIcon, appName: secondAppName)
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

/// Individual Apple Glass frosted blur panel with visual effect backing, centered app icon, and name.
final class PairedBlurPanel: NSView {
    private let visualEffectView = NSVisualEffectView()
    private let canvasView = PairedBlurCanvasView()
    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
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

        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.alphaValue = 1.0
        addSubview(visualEffectView)

        canvasView.onDraw = { [weak self] rect in
            self?.drawOverlay(in: rect)
        }
        addSubview(canvasView)

        // Center app icon
        iconImageView.wantsLayer = true
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.shadow = createDropShadow(radius: 8.0, opacity: 0.40)
        addSubview(iconImageView)

        // Center app title label
        titleLabel.wantsLayer = true
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.shadow = createDropShadow(radius: 4.0, opacity: 0.30)
        addSubview(titleLabel)
    }

    func configure(appIcon: NSImage?, appName: String?) {
        iconImageView.image = appIcon
        titleLabel.stringValue = appName ?? ""
        needsLayout = true
    }

    override func layout() {
        super.layout()
        visualEffectView.frame = bounds
        canvasView.frame = bounds
        layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.cornerRadius = cornerRadius

        let b = bounds
        let isTooSmall = b.width < 100 || b.height < 120
        iconImageView.isHidden = isTooSmall || (iconImageView.image == nil)
        titleLabel.isHidden = isTooSmall || titleLabel.stringValue.isEmpty

        guard !isTooSmall else { return }

        let iconSize: CGFloat = 64.0
        let labelHeight: CGFloat = 18.0
        let spacing: CGFloat = 8.0
        let totalContentHeight = iconSize + spacing + labelHeight

        let startY = (b.height - totalContentHeight) / 2.0
        let iconX = (b.width - iconSize) / 2.0

        titleLabel.frame = CGRect(x: 16.0, y: startY, width: max(0, b.width - 32.0), height: labelHeight)
        iconImageView.frame = CGRect(x: iconX, y: startY + labelHeight + spacing, width: iconSize, height: iconSize)
    }

    private func drawOverlay(in dirtyRect: NSRect) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)

        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

        // Frosted glass tint with high diffusion: completely obscures background text and broken UI
        // while maintaining authentic translucent Apple Glass depth
        let tint = isDark
            ? NSColor(white: 0.14, alpha: 0.68)
            : NSColor(white: 0.94, alpha: 0.72)
        tint.setFill()
        bgPath.fill()

        // Luminous high-definition outer rim
        let rimColor = isDark
            ? NSColor(white: 1.0, alpha: 0.28)
            : NSColor(white: 0.0, alpha: 0.18)
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
                ? NSColor(white: 1.0, alpha: 0.40)
                : NSColor(white: 1.0, alpha: 0.75)
            highlightColor.setStroke()
            topHighlightPath.lineWidth = 1.0
            topHighlightPath.stroke()
        }
    }

    private func createDropShadow(radius: CGFloat, opacity: Float) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(CGFloat(opacity))
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        shadow.shadowBlurRadius = radius
        return shadow
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
