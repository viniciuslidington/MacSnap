import CoreGraphics
import Foundation

/// Recognizes one window-drag gesture from its first observed movement through release.
/// The payload is opaque: production retains a window, while tests can use a plain value.
/// Callers resolve native window facts only when the first movement needs admission.
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
        case candidate(window: Window, origin: CGPoint)
        case dragging(window: Window)
        case ignored
    }

    private var state: State = .idle
    private let movementThreshold: CGFloat = 14

    var window: Window? {
        switch state {
        case .candidate(let window, _), .dragging(let window): window
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
        candidate resolveCandidate: () -> Candidate?
    ) -> Bool {
        switch state {
        case .ignored, .dragging:
            return false

        case .candidate(let window, let origin):
            guard hypot(point.x - origin.x, point.y - origin.y) >= movementThreshold else {
                return false
            }
            state = .dragging(window: window)
            return true

        case .idle:
            guard let visibleFrame,
                  visibleFrame.contains(point),
                  point.y < visibleFrame.maxY - 1,
                  let candidate = resolveCandidate(),
                  !candidate.isDesktop,
                  !candidate.isOwnWindow,
                  WindowElement.isPointInHeaderRegion(point, windowFrame: candidate.frame) else {
                state = .ignored
                return false
            }
            state = .candidate(window: candidate.window, origin: point)
            return false
        }
    }

    /// Finishes every gesture, including rejected and sub-threshold attempts.
    mutating func release() -> Release {
        let result = Release(window: window, wasDragging: isDragging)
        state = .idle
        return result
    }

    /// Discards captured window facts. Suppression prevents this same held gesture restarting.
    mutating func reset(ignoringUntilRelease: Bool = false) {
        state = ignoringUntilRelease ? .ignored : .idle
    }
}
