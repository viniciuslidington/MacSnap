import Foundation
import CoreGraphics

/// Represents the possible snap target zones on a display,
/// including advanced support for symmetric and asymmetric (2/3 and 1/3) layouts.
public enum SnapZone: Sendable, Equatable {
    // Standard Layouts
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize

    // Quadrants
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter

    // Horizontal Columns (16:9 / Ultrawide)
    case leftThird
    case centerThird
    case rightThird

    // Asymmetric Horizontal Layouts (2/3 and 1/3 splits)
    case leftTwoThirds    // Left 2/3
    case rightOneThird    // Right 1/3 (paired with leftTwoThirds)
    case leftOneThird     // Left 1/3 (same as leftThird)
    case rightTwoThirds   // Right 2/3 (paired with leftOneThird)

    // Vertical Partitions (Portrait Displays)
    case topThird         // Top 1/3
    case middleThird      // Middle 1/3
    case bottomThird      // Bottom 1/3
    case topTwoThirds     // Top 2/3 (paired with bottomThird)
    case bottomTwoThirds  // Bottom 2/3 (paired with topThird - inverse)

    /// Calculates the target rectangle (in Cocoa screen coordinates) for the zone.
    /// - Parameter visibleFrame: The visible screen frame (excluding Dock and Menu bar).
    /// - Returns: The resulting CGRect where the window should be positioned.
    public func targetRect(for visibleFrame: CGRect) -> CGRect {
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let width = visibleFrame.width
        let height = visibleFrame.height
        let halfWidth = width / 2.0
        let halfHeight = height / 2.0

        let thirdWidth = width / 3.0
        let twoThirdsWidth = width * (2.0 / 3.0)

        let thirdHeight = height / 3.0
        let twoThirdsHeight = height * (2.0 / 3.0)

        switch self {
        case .leftHalf:
            return CGRect(x: x, y: y, width: halfWidth, height: height)

        case .rightHalf:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: height)

        case .topHalf:
            return CGRect(x: x, y: y + halfHeight, width: width, height: halfHeight)

        case .bottomHalf:
            return CGRect(x: x, y: y, width: width, height: halfHeight)

        case .maximize:
            return visibleFrame

        // Quadrants
        case .topLeftQuarter:
            return CGRect(x: x, y: y + halfHeight, width: halfWidth, height: halfHeight)

        case .topRightQuarter:
            return CGRect(x: x + halfWidth, y: y + halfHeight, width: halfWidth, height: halfHeight)

        case .bottomLeftQuarter:
            return CGRect(x: x, y: y, width: halfWidth, height: halfHeight)

        case .bottomRightQuarter:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: halfHeight)

        // Horizontal Columns and Thirds (16:9 / Ultrawide)
        case .leftThird, .leftOneThird:
            return CGRect(x: x, y: y, width: thirdWidth, height: height)

        case .centerThird:
            return CGRect(x: x + thirdWidth, y: y, width: thirdWidth, height: height)

        case .rightThird, .rightOneThird:
            return CGRect(x: x + twoThirdsWidth, y: y, width: thirdWidth, height: height)

        // Asymmetric Horizontal Splits (2/3 and 1/3)
        case .leftTwoThirds:
            return CGRect(x: x, y: y, width: twoThirdsWidth, height: height)

        case .rightTwoThirds:
            return CGRect(x: x + thirdWidth, y: y, width: twoThirdsWidth, height: height)

        // Vertical Partitions (Portrait Displays)
        case .topThird:
            return CGRect(x: x, y: y + (thirdHeight * 2.0), width: width, height: thirdHeight)

        case .middleThird:
            return CGRect(x: x, y: y + thirdHeight, width: width, height: thirdHeight)

        case .bottomThird:
            return CGRect(x: x, y: y, width: width, height: thirdHeight)

        case .topTwoThirds:
            return CGRect(x: x, y: y + thirdHeight, width: width, height: twoThirdsHeight)

        case .bottomTwoThirds:
            return CGRect(x: x, y: y, width: width, height: twoThirdsHeight)
        }
    }
}
