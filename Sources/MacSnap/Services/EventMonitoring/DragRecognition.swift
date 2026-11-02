import CoreGraphics
import Foundation

/// Recognizes one window-drag gesture from its first observed movement through release.
/// The payload is opaque: production retains a window, while tests can use a plain value.
/// Candidate identity is resolved once; callers may revalidate its size during motion.
struct DragRecognition<Window> {
    struct Candidate {
        let window: Window
        let frame: CGRect
        var isDesktop = false
        var isOwnWindow = false
    }

    struct Release {
        let window: Window?
        let wasDragging: Bool
    }

    private enum State {
        case idle
        case candidate(window: Window, origin: CGPoint, initialSize: CGSize)
        case dragging(window: Window, initialSize: CGSize)
        case ignored
    }

    private var state: State = .idle
    private let movementThreshold: CGFloat = 14
    private let sizeTolerance: CGFloat = 4
    private let resizeBorderInset: CGFloat = 4

    var window: Window? {
        switch state {
        case .candidate(let window, _, _), .dragging(let window, _): window
        case .idle, .ignored: nil
        }
    }

    var isDragging: Bool {
        if case .dragging = state { return true }
        return false
    }

    var isIgnored: Bool {
        if case .ignored = state { return true }
        return false
    }

    /// Returns true only when the gesture first crosses the intentional movement threshold.
    /// A rejection is latched until release, even if later movements enter an eligible header.
    @discardableResult
    mutating func drag(
        at point: CGPoint,
        visibleFrame: CGRect?,
        frameForWindow: ((Window) -> CGRect?)? = nil,
        candidate resolveCandidate: () -> Candidate?
    ) -> Bool {
        validateSize(using: frameForWindow)
        switch state {
        case .ignored, .dragging:
            return false

        case .candidate(let window, let origin, let initialSize):
            guard hypot(point.x - origin.x, point.y - origin.y) >= movementThreshold else {
                return false
            }
            state = .dragging(window: window, initialSize: initialSize)
            return true

        case .idle:
            guard let visibleFrame,
                  visibleFrame.contains(point),
                  point.y < visibleFrame.maxY - 1,
                  let candidate = resolveCandidate(),
                  !candidate.isDesktop,
                  !candidate.isOwnWindow,
                  // Keep the boundary strip available for native resize handles,
                  // even when a minimum-size constraint prevents a frame change.
                  candidate.frame.insetBy(dx: resizeBorderInset, dy: resizeBorderInset).contains(point),
                  WindowElement.isPointInHeaderRegion(point, windowFrame: candidate.frame) else {
                state = .ignored
                return false
            }
            state = .candidate(window: candidate.window, origin: point, initialSize: candidate.frame.size)
            return false
        }
    }

    /// Finishes every gesture, including rejected and sub-threshold attempts.
    mutating func release(frameForWindow: ((Window) -> CGRect?)? = nil) -> Release {
        validateSize(using: frameForWindow)
        let result = Release(window: window, wasDragging: isDragging)
        state = .idle
        return result
    }

    private mutating func validateSize(using frameForWindow: ((Window) -> CGRect?)?) {
        guard let frameForWindow else { return }
        let window: Window
        let initialSize: CGSize
        switch state {
        case .candidate(let captured, _, let size), .dragging(let captured, let size):
            window = captured
            initialSize = size
        case .idle, .ignored:
            return
        }
        guard let frame = frameForWindow(window),
              frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
              abs(frame.width - initialSize.width) <= sizeTolerance,
              abs(frame.height - initialSize.height) <= sizeTolerance else {
            state = .ignored
            return
        }
    }

    /// Discards captured window facts. Suppression prevents this same held gesture restarting.
    mutating func reset(ignoringUntilRelease: Bool = false) {
        state = ignoringUntilRelease ? .ignored : .idle
    }
}
