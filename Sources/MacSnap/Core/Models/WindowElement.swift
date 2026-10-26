import Foundation
import ApplicationServices
import CoreGraphics
import Cocoa

/// Encapsulates a macOS window retrieved via the Accessibility API (`AXUIElement`).
/// Provides safe, strongly typed methods to query and modify size and position.
public final class WindowElement: @unchecked Sendable, Identifiable {
    public let rawElement: AXUIElement
    public let pid: pid_t

    public init(element: AXUIElement, pid: pid_t) {
        self.rawElement = element
        self.pid = pid
    }

    /// Window title (or nil if inaccessible).
    public var title: String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(rawElement, kAXTitleAttribute as CFString, &value)
        guard result == .success, let titleStr = value as? String else { return nil }
        return titleStr
    }

    /// Window accessibility role (e.g., "AXWindow").
    public var role: String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(rawElement, kAXRoleAttribute as CFString, &value)
        guard result == .success, let roleStr = value as? String else { return nil }
        return roleStr
    }

    /// Window accessibility subrole (e.g., "AXStandardWindow", "AXDesktopWindow", "AXDialog").
    public var subrole: String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(rawElement, kAXSubroleAttribute as CFString, &value)
        guard result == .success, let subroleStr = value as? String else { return nil }
        return subroleStr
    }

    /// Checks if this element represents the macOS Finder desktop wallpaper window.
    public var isDesktopWindow: Bool {
        subrole == "AXDesktopWindow"
    }

    /// Running application instance representing the owning process.
    public var runningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: pid)
    }

    /// Application icon image, falling back to standard application bundle icon.
    public var appIcon: NSImage? {
        if let icon = runningApplication?.icon {
            return icon
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    /// Application localized display name.
    public var appName: String? {
        runningApplication?.localizedName ?? title ?? "App"
    }

    /// Returns the window frame in Accessibility API coordinates.
    public var axFrame: CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(rawElement, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(rawElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posVal = posValue, let sizeVal = sizeValue else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero

        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

        return CGRect(origin: point, size: size)
    }

    /// Returns the window frame converted to Cocoa coordinates.
    public func cocoaFrame(primaryScreenHeight: CGFloat) -> CGRect? {
        guard let axFrame = self.axFrame else { return nil }
        return ScreenGeometry.axToCocoa(axRect: axFrame, primaryScreenHeight: primaryScreenHeight)
    }

    /// Sets new position and size in Accessibility coordinates.
    /// - Parameters:
    ///   - newAXFrame: The target CGRect in AX coordinates.
    /// - Returns: Bool indicating whether the update was accepted.
    @discardableResult
    public func setAXFrame(_ newAXFrame: CGRect) -> Bool {
        var point = newAXFrame.origin
        var size = newAXFrame.size

        guard let posValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        // Multi-pass anti-clamping:
        // On macOS, the ordering between position and size is critical:
        // If size is set while the window is still at an old position, the WindowServer
        // clamps the size against the current screen boundary before moving, causing truncated windows.
        // Applying position -> size -> position -> size guarantees both expanding and shrinking
        // windows reach the exact target frame without truncation.

        // Pass 1: Move to target position first to clear expansion headroom
        let posRes1 = AXUIElementSetAttributeValue(rawElement, kAXPositionAttribute as CFString, posValue)
        let sizeRes1 = AXUIElementSetAttributeValue(rawElement, kAXSizeAttribute as CFString, sizeValue)

        if posRes1 == .apiDisabled || sizeRes1 == .apiDisabled {
            print("[MacSnap] ❌ ACCESSIBILITY ERROR: kAXErrorAPIDisabled when resizing PID \(pid).")
            print("[MacSnap] 💡 Please enable MacSnap in System Settings > Privacy & Security > Accessibility.")
            return false
        }

        // Pass 2: Reapply position and size to settle any clamped intermediate states
        _ = AXUIElementSetAttributeValue(rawElement, kAXPositionAttribute as CFString, posValue)
        _ = AXUIElementSetAttributeValue(rawElement, kAXSizeAttribute as CFString, sizeValue)

        // Pass 3 (Verification): If actual frame deviates by > 4px, enforce final target
        if let current = self.axFrame {
            let dw = abs(current.width - newAXFrame.width)
            let dh = abs(current.height - newAXFrame.height)
            let dx = abs(current.origin.x - newAXFrame.origin.x)
            let dy = abs(current.origin.y - newAXFrame.origin.y)

            if dw > 4 || dh > 4 || dx > 4 || dy > 4 {
                _ = AXUIElementSetAttributeValue(rawElement, kAXPositionAttribute as CFString, posValue)
                _ = AXUIElementSetAttributeValue(rawElement, kAXSizeAttribute as CFString, sizeValue)
            }
        }

        return true
    }

    /// Sets new position and size using Cocoa coordinates (internally converted to AX).
    @discardableResult
    public func setCocoaFrame(_ cocoaRect: CGRect, primaryScreenHeight: CGFloat) -> Bool {
        let axFrame = ScreenGeometry.cocoaToAX(cocoaRect: cocoaRect, primaryScreenHeight: primaryScreenHeight)
        return setAXFrame(axFrame)
    }

    /// Checks if the window supports resizing.
    public var isResizable: Bool {
        var isSettable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(rawElement, kAXSizeAttribute as CFString, &isSettable)
        return result == .success && isSettable.boolValue
    }

    /// Determines if a point in Cocoa coordinates falls within the upper header/tab bar region of this window.
    /// - Parameters:
    ///   - point: The mouse point in Cocoa coordinates.
    ///   - primaryScreenHeight: The primary screen height for coordinate translation.
    ///   - maxHeaderHeight: The maximum height in points from the top edge considered the header/tab bar (default: 65.0).
    /// - Returns: True if the point is within the upper header/tab bar zone of the window.
    public func isPointInHeaderRegion(_ point: CGPoint, primaryScreenHeight: CGFloat, maxHeaderHeight: CGFloat = 65.0) -> Bool {
        guard let frame = cocoaFrame(primaryScreenHeight: primaryScreenHeight) else { return false }
        return WindowElement.isPointInHeaderRegion(point, windowFrame: frame, maxHeaderHeight: maxHeaderHeight)
    }

    /// Static calculation to determine if a point falls within a window's upper header/tab bar region.
    /// - Parameters:
    ///   - point: The mouse point in Cocoa coordinates.
    ///   - windowFrame: Window frame in Cocoa coordinates.
    ///   - maxHeaderHeight: The maximum height in points from the top edge considered the header/tab bar (default: 65.0).
    /// - Returns: True if the point falls strictly inside the top header/tab bar.
    public static func isPointInHeaderRegion(_ point: CGPoint, windowFrame: CGRect, maxHeaderHeight: CGFloat = 65.0) -> Bool {
        let tolerance: CGFloat = 2.0
        guard point.x >= windowFrame.minX - tolerance && point.x <= windowFrame.maxX + tolerance &&
              point.y >= windowFrame.minY - tolerance && point.y <= windowFrame.maxY + tolerance else {
            return false
        }
        let headerHeight = min(maxHeaderHeight, windowFrame.height * 0.5)
        let minHeaderY = windowFrame.maxY - headerHeight
        return point.y >= minHeaderY && point.y <= windowFrame.maxY + tolerance
    }
}
