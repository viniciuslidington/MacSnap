import Foundation
import Cocoa
import CoreGraphics

/// Manages display discovery and calculates screen dimensions and visibility across monitors.
public final class ScreenService: ScreenServiceProtocol, @unchecked Sendable {
    public static let shared = ScreenService()

    public init() {}

    public var screens: [NSScreen] {
        return NSScreen.screens
    }

    public var primaryScreen: NSScreen? {
        return NSScreen.screens.first
    }

    public var primaryScreenHeight: CGFloat {
        return primaryScreen?.frame.height ?? 0.0
    }

    public func screenContaining(point: CGPoint) -> NSScreen? {
        // In Cocoa, displays exist in the same global coordinates where mouse location resides
        return screens.first { $0.frame.contains(point) } ?? primaryScreen
    }

    public func screenContaining(rect: CGRect) -> NSScreen? {
        // Finds the screen with the largest overlap area with the given rectangle
        var bestScreen: NSScreen?
        var maxIntersectionArea: CGFloat = 0

        for screen in screens {
            let intersection = screen.frame.intersection(rect)
            let area = intersection.width * intersection.height
            if area > maxIntersectionArea {
                maxIntersectionArea = area
                bestScreen = screen
            }
        }

        return bestScreen ?? primaryScreen
    }
}

extension NSScreen {
    /// Indicates whether the display is oriented vertically (height greater than width).
    public var isPortrait: Bool {
        return frame.height > frame.width
    }

    /// Unique numeric display identifier in macOS (CGDirectDisplayID).
    public var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let id = deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(id.uint32Value)
        }
        return CGDirectDisplayID(abs(frame.origin.x.hashValue ^ frame.origin.y.hashValue))
    }
}
