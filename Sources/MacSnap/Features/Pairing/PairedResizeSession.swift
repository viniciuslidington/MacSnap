import Cocoa

/// Drawing is an internal adapter: lifecycle tests need no screen or NSPanel.
@MainActor
protocol PairedResizePresenting: AnyObject {
    func present(pair: PairedSplit)
    func update(pair: PairedSplit)
    func dismiss(animated: Bool)
}

/// Owns one gesture and its readback. It never switches to another pair.
@MainActor
final class PairedResizeSession {
    enum Phase {
        case idle, dragging, settling, finished, cancelled, invalidated
    }

    private(set) var phase: Phase = .idle
    private let pair: PairedSplit
    private let primaryScreenHeight: CGFloat
    private let presentation: any PairedResizePresenting
    private let scheduler: any ActionScheduling
    private let isCurrent: () -> Bool
    private let onInvalidated: () -> Void
    private var pendingSettlement: (any ScheduledAction)?

    init(
        pair: PairedSplit,
        primaryScreenHeight: CGFloat,
        presentation: any PairedResizePresenting,
        scheduler: any ActionScheduling = MainActorScheduler.shared,
        isCurrent: @escaping () -> Bool,
        onInvalidated: @escaping () -> Void
    ) {
        self.pair = pair
        self.primaryScreenHeight = primaryScreenHeight
        self.presentation = presentation
        self.scheduler = scheduler
        self.isCurrent = isCurrent
        self.onInvalidated = onInvalidated
    }

    @discardableResult
    func begin() -> Bool {
        guard phase == .idle else { return false }
        guard isCurrent() else { cancel(); return false }
        guard validGeometry, observedFrames() != nil else { invalidate(); return false }
        phase = .dragging
        presentation.present(pair: pair)
        return true
    }

    func update(to cursorCoordinate: CGFloat) {
        guard phase == .dragging else { return }
        guard isCurrent() else { abandonStaleWork(); return }
        guard cursorCoordinate.isFinite, observedFrames() != nil else { invalidate(); return }
        pair.updateRatioOnly(from: cursorCoordinate)
        presentation.update(pair: pair)
    }

    func finish() {
        guard phase == .dragging else { return }
        guard isCurrent() else { abandonStaleWork(); return }
        guard observedFrames() != nil else { invalidate(); return }
        presentation.dismiss(animated: true)
        guard pair.applyCurrentSplit(primaryScreenHeight: primaryScreenHeight) else {
            invalidate()
            return
        }
        presentation.update(pair: pair)
        phase = .settling
        pendingSettlement = scheduler.schedule(after: 0.06) { [weak self] in
            self?.settle()
        }
    }

    func cancel() {
        pendingSettlement?.cancel()
        pendingSettlement = nil
        guard phase != .invalidated && phase != .cancelled else { return }
        let wasActive = phase == .dragging || phase == .settling
        phase = .cancelled
        if wasActive { presentation.dismiss(animated: false) }
    }

    private var validGeometry: Bool {
        let f = pair.visibleFrame
        return primaryScreenHeight.isFinite && primaryScreenHeight > 0 &&
            valid(f) && pair.ratio.isFinite && !pair.firstWindow.isSameWindow(as: pair.secondWindow)
    }

    private func valid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite &&
            frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }

    private func observedFrames() -> (CGRect, CGRect)? {
        guard pair.firstWindow.isResizable, pair.secondWindow.isResizable,
              let first = pair.firstWindow.cocoaFrame(primaryScreenHeight: primaryScreenHeight),
              let second = pair.secondWindow.cocoaFrame(primaryScreenHeight: primaryScreenHeight),
              valid(first), valid(second) else { return nil }
        return (first, second)
    }

    private func settle() {
        guard phase == .settling else { return }
        pendingSettlement = nil
        guard isCurrent() else { abandonStaleWork(); return }
        guard let (first, second) = observedFrames(), validGeometry else { invalidate(); return }

        let visible = pair.visibleFrame
        let flushSecond: CGRect
        let needsAlignment: Bool
        switch pair.orientation {
        case .horizontal:
            let remaining = visible.maxX - first.maxX
            guard abs(first.minX - visible.minX) <= 4, remaining >= 100,
                  representableRatio((first.maxX - visible.minX) / visible.width, span: visible.width) else {
                invalidate()
                return
            }
            flushSecond = CGRect(x: first.maxX, y: visible.minY, width: remaining, height: visible.height)
            needsAlignment = abs(second.minX - first.maxX) > 4 || abs(second.maxX - visible.maxX) > 4
        case .vertical:
            let remaining = first.minY - visible.minY
            guard abs(first.maxY - visible.maxY) <= 4, remaining >= 100,
                  representableRatio((visible.maxY - first.minY) / visible.height, span: visible.height) else {
                invalidate()
                return
            }
            flushSecond = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: remaining)
            needsAlignment = abs(second.maxY - first.minY) > 4 || abs(second.minY - visible.minY) > 4
        }

        if needsAlignment && !pair.secondWindow.setCocoaFrame(flushSecond, primaryScreenHeight: primaryScreenHeight) {
            invalidate()
            return
        }

        // Requested frames are not evidence of accepted frames. Refuse an impossible
        // pairing after one bounded correction rather than repeatedly fighting an app.
        guard let (observedFirst, observedSecond) = observedFrames() else { invalidate(); return }
        let ratio: CGFloat
        switch pair.orientation {
        case .horizontal:
            guard abs(observedFirst.minX - visible.minX) <= 4,
                  abs(observedFirst.maxX - observedSecond.minX) <= 4,
                  abs(observedSecond.maxX - visible.maxX) <= 4 else { invalidate(); return }
            ratio = (observedFirst.maxX - visible.minX) / visible.width
        case .vertical:
            guard abs(observedFirst.maxY - visible.maxY) <= 4,
                  abs(observedFirst.minY - observedSecond.maxY) <= 4,
                  abs(observedSecond.minY - visible.minY) <= 4 else { invalidate(); return }
            ratio = (visible.maxY - observedFirst.minY) / visible.height
        }
        let span = pair.orientation == .horizontal ? visible.width : visible.height
        guard representableRatio(ratio, span: span),
              let admitted = PairGeometry.split(first: observedFirst, second: observedSecond, in: visible, gapTolerance: 4, edgeTolerance: 4),
              admitted.orientation == pair.orientation, admitted.firstIsLeading else { invalidate(); return }
        pair.ratio = ratio
        phase = .finished
        presentation.update(pair: pair)
    }

    private func representableRatio(_ ratio: CGFloat, span: CGFloat) -> Bool {
        // One logical point accounts for calculateFrames' rounding at either clamp.
        ratio.isFinite && ratio >= 0.15 - 1 / span && ratio <= 0.85 + 1 / span
    }

    private func abandonStaleWork() {
        pendingSettlement?.cancel()
        pendingSettlement = nil
        phase = .cancelled
        // A stale operation must not dismiss another operation's presentation.
    }

    private func invalidate() {
        guard isCurrent() else { abandonStaleWork(); return }
        pendingSettlement?.cancel()
        pendingSettlement = nil
        phase = .invalidated
        presentation.dismiss(animated: false)
        onInvalidated()
    }
}

/// AppKit adapter for the lifecycle's presentation seam.
@MainActor
final class ScreenPairResizePresentation: PairedResizePresenting {
    private weak var state: ScreenPairState?
    private let screen: NSScreen

    init(state: ScreenPairState, screen: NSScreen) {
        self.state = state
        self.screen = screen
    }

    func present(pair: PairedSplit) {
        let (first, second) = pair.calculateFrames()
        state?.resizeOverlay.present(
            on: screen,
            firstRect: first,
            secondRect: second,
            firstAppIcon: pair.firstWindow.appIcon,
            secondAppIcon: pair.secondWindow.appIcon,
            firstAppName: pair.firstWindow.appName,
            secondAppName: pair.secondWindow.appName,
            animated: true
        )
    }

    func update(pair: PairedSplit) {
        let (first, second) = pair.calculateFrames()
        state?.dividerWindow.update(for: pair)
        state?.resizeOverlay.update(firstRect: first, secondRect: second)
    }

    func dismiss(animated: Bool) {
        state?.resizeOverlay.dismiss(animated: animated)
    }
}
