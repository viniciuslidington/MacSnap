import ApplicationServices
import CoreGraphics
import Foundation

/// The internal seam for window frame I/O. Coordinates use the Accessibility convention.
protocol WindowFrameAccess: Sendable {
    var frame: CGRect? { get }
    var isResizable: Bool { get }
    /// Acceptance of the native writes does not imply that the application reached the target.
    func setFrame(_ frame: CGRect) -> Bool
}

/// The only stored state is an immutable native handle. AX requests do not mutate Swift state.
/// AppKit callers serialize user interactions on the main actor; tests substitute a locked adapter.
final class AXWindowFrameAccess: WindowFrameAccess, @unchecked Sendable {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    var frame: CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let point = Self.point(from: position),
              let dimensions = Self.size(from: size) else { return nil }
        let rect = CGRect(origin: point, size: dimensions)
        return Self.isUsable(rect) ? rect : nil
    }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    func setFrame(_ frame: CGRect) -> Bool {
        guard Self.isUsable(frame) else { return false }
        var origin = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }

        // Move before resizing to avoid clamping expansion against the previous position.
        // Every write must be accepted; failed native calls must not register a successful snap.
        func apply() -> Bool {
            guard AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue) == .success else { return false }
            return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success
        }
        guard apply(), apply(), let observed = self.frame else { return false }
        if abs(observed.minX - frame.minX) > 4 || abs(observed.minY - frame.minY) > 4
            || abs(observed.width - frame.width) > 4 || abs(observed.height - frame.height) > 4 {
            return apply()
        }
        return true
    }

    static func isUsable(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }

    static func point(from value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // CF type identity was verified before the bridge cast.
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    static func size(from value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }
}
