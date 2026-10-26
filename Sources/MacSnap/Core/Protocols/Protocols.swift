import Foundation
import CoreGraphics
import Cocoa

/// Contract for services interacting with the macOS Accessibility API.
public protocol AccessibilityServiceProtocol: Sendable {
    /// Checks whether accessibility permissions are granted in System Settings.
    /// - Parameter promptIfNeeded: If true, displays the system dialog requesting authorization.
    func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool

    /// Returns the currently focused window.
    func getFocusedWindow() -> WindowElement?

    /// Returns the window located under a specific point (in Accessibility coordinates).
    func getWindowUnderPoint(_ point: CGPoint) -> WindowElement?
}

/// Contract for display management and screen geometry calculations.
public protocol ScreenServiceProtocol: Sendable {
    /// All active displays in macOS.
    var screens: [NSScreen] { get }

    /// The primary display (whose bottom-left corner is origin (0,0) in Cocoa).
    var primaryScreen: NSScreen? { get }

    /// Height of the primary display (required for coordinate conversions with Accessibility).
    var primaryScreenHeight: CGFloat { get }

    /// Finds the display containing the specified point (in Cocoa coordinates).
    func screenContaining(point: CGPoint) -> NSScreen?

    /// Finds the display containing the specified rectangle.
    func screenContaining(rect: CGRect) -> NSScreen?
}

/// Contract for the window snapping engine.
@MainActor
public protocol WindowSnappingProtocol: AnyObject {
    /// Applies a snap target zone to the currently focused window.
    func snapFocusedWindow(to zone: SnapZone)

    /// Applies a snap target zone to a specific window on a target display.
    func snapWindow(_ window: WindowElement, to zone: SnapZone, on screen: NSScreen)
}

/// Contract for mouse and keyboard event monitoring.
@MainActor
public protocol EventMonitoringProtocol: AnyObject {
    /// Starts monitoring mouse drag events for snap detection.
    func startMonitoring()

    /// Stops event monitoring.
    func stopMonitoring()
}
