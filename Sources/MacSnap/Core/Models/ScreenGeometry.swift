import Foundation
import CoreGraphics
import Cocoa

/// Utilities for geometric conversion between the Cocoa coordinate system
/// (origin at bottom-left) and the Accessibility API coordinate system (origin at top-left).
public struct ScreenGeometry {

    /// Converts a rectangle from Cocoa coordinates to the Accessibility API coordinate system.
    /// - Parameters:
    ///   - cocoaRect: Rectangle in Cocoa coordinates.
    ///   - primaryScreenHeight: Total height of the primary display (NSScreen.screens.first?.frame.height).
    /// - Returns: Rectangle formatted for the Accessibility API (AXUIElement).
    public static func cocoaToAX(cocoaRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let axX = cocoaRect.origin.x
        let axY = primaryScreenHeight - (cocoaRect.origin.y + cocoaRect.height)
        return CGRect(x: axX, y: axY, width: cocoaRect.width, height: cocoaRect.height)
    }

    /// Converts a rectangle from Accessibility API coordinates to the Cocoa coordinate system.
    /// - Parameters:
    ///   - axRect: Rectangle in Accessibility coordinates.
    ///   - primaryScreenHeight: Total height of the primary display.
    /// - Returns: Rectangle formatted for Cocoa (NSScreen, NSWindow).
    public static func axToCocoa(axRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let cocoaX = axRect.origin.x
        let cocoaY = primaryScreenHeight - (axRect.origin.y + axRect.height)
        return CGRect(x: cocoaX, y: cocoaY, width: axRect.width, height: axRect.height)
    }

    /// Converts a point from the Accessibility API to Cocoa coordinates.
    public static func axPointToCocoa(axPoint: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        return CGPoint(x: axPoint.x, y: primaryScreenHeight - axPoint.y)
    }

    /// Converts a point from Cocoa to Accessibility API coordinates.
    public static func cocoaPointToAX(cocoaPoint: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        return CGPoint(x: cocoaPoint.x, y: primaryScreenHeight - cocoaPoint.y)
    }
}
