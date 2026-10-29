import Foundation
import ApplicationServices
import CoreGraphics
import Cocoa

/// Encapsulates a macOS window retrieved via the Accessibility API (`AXUIElement`).
/// Provides safe, strongly typed methods to query and modify size and position.
/// The wrapper is immutable; its frame adapter is Sendable. The unchecked conformance
/// bridges the imported immutable CF handle, not mutable Swift window state.
public final class WindowElement: @unchecked Sendable, Identifiable {
    public let rawElement: AXUIElement
    public let pid: pid_t
    private let frameAccess: any WindowFrameAccess
    private let scriptedIdentity: UUID?

    public init(element: AXUIElement, pid: pid_t) {
        self.rawElement = element
        self.pid = pid
        self.frameAccess = AXWindowFrameAccess(element: element)
        self.scriptedIdentity = nil
    }

    /// Internal injection keeps native AX handles out of deterministic frame tests.
    init(element: AXUIElement, pid: pid_t, frameAccess: any WindowFrameAccess, identity: UUID? = nil) {
        self.rawElement = element
        self.pid = pid
        self.frameAccess = frameAccess
        self.scriptedIdentity = identity
    }

    /// Process identity alone cannot distinguish two windows owned by the same application.
    public func isSameWindow(as other: WindowElement) -> Bool {
        guard pid == other.pid else { return false }
        if scriptedIdentity != nil || other.scriptedIdentity != nil {
            return scriptedIdentity != nil && scriptedIdentity == other.scriptedIdentity
        }
        return CFEqual(rawElement, other.rawElement)
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
        guard let frame = frameAccess.frame, AXWindowFrameAccess.isUsable(frame) else { return nil }
        return frame
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
        guard AXWindowFrameAccess.isUsable(newAXFrame) else { return false }
        return frameAccess.setFrame(newAXFrame)
    }

    /// Sets new position and size using Cocoa coordinates (internally converted to AX).
    @discardableResult
    public func setCocoaFrame(_ cocoaRect: CGRect, primaryScreenHeight: CGFloat) -> Bool {
        let axFrame = ScreenGeometry.cocoaToAX(cocoaRect: cocoaRect, primaryScreenHeight: primaryScreenHeight)
        return setAXFrame(axFrame)
    }

    /// Checks if the window supports resizing.
    public var isResizable: Bool {
        frameAccess.isResizable
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
