import Foundation
import CoreGraphics
import Cocoa

/// Orientation of the split between two paired windows.
public enum SplitOrientation: Sendable {
    case horizontal // Windows side by side (Left and Right)
    case vertical   // Windows stacked (Top and Bottom, essential for portrait monitors)
}

/// Represents a pair of snapped windows (similar to Windows Snap Assist).
/// Supports both horizontal splits (Left/Right) and vertical splits (Top/Bottom),
/// with magnetic snapping at common ratios and dynamic overlap prevention.
public final class PairedSplit {
    public let firstWindow: WindowElement   // Left or Top window
    public let secondWindow: WindowElement  // Right or Bottom window
    public let orientation: SplitOrientation
    public var visibleFrame: CGRect

    /// Ratio of the space occupied by the first window (between 0.15 and 0.85).
    /// - For horizontal: width ratio of the left window.
    /// - For vertical: height ratio of the top window.
    public var ratio: CGFloat {
        didSet {
            ratio = min(max(ratio, 0.15), 0.85)
        }
    }

    public init(
        firstWindow: WindowElement,
        secondWindow: WindowElement,
        orientation: SplitOrientation = .horizontal,
        visibleFrame: CGRect,
        ratio: CGFloat = 0.5
    ) {
        self.firstWindow = firstWindow
        self.secondWindow = secondWindow
        self.orientation = orientation
        self.visibleFrame = visibleFrame
        self.ratio = min(max(ratio, 0.15), 0.85)
    }

    // Compatibility with previous initializer (left/right)
    public convenience init(
        leftWindow: WindowElement,
        rightWindow: WindowElement,
        visibleFrame: CGRect,
        ratio: CGFloat = 0.5
    ) {
        self.init(
            firstWindow: leftWindow,
            secondWindow: rightWindow,
            orientation: .horizontal,
            visibleFrame: visibleFrame,
            ratio: ratio
        )
    }

    public var leftWindow: WindowElement { firstWindow }
    public var rightWindow: WindowElement { secondWindow }
    public var topWindow: WindowElement { firstWindow }
    public var bottomWindow: WindowElement { secondWindow }

    /// Calculates the rectangles in Cocoa coordinates for the first and second window.
    public func calculateFrames() -> (first: CGRect, second: CGRect) {
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let width = visibleFrame.width
        let height = visibleFrame.height

        switch orientation {
        case .horizontal:
            let leftWidth = (width * ratio).rounded()
            let rightWidth = width - leftWidth
            let leftRect = CGRect(x: x, y: y, width: leftWidth, height: height)
            let rightRect = CGRect(x: x + leftWidth, y: y, width: rightWidth, height: height)
            return (leftRect, rightRect)

        case .vertical:
            let bottomHeight = (height * (1.0 - ratio)).rounded()
            let topHeight = height - bottomHeight
            // In Cocoa, bottom window starts at y, and top starts at y + bottomHeight
            let bottomRect = CGRect(x: x, y: y, width: width, height: bottomHeight)
            let topRect = CGRect(x: x, y: y + bottomHeight, width: width, height: topHeight)
            return (topRect, bottomRect)
        }
    }

    /// Exact position of the central divider based on the real edge reached by the first window:
    /// Coordinate of the divider dividing the two windows based on current ratio.
    /// - If horizontal, returns the X coordinate where the left window ends.
    /// - If vertical, returns the Y coordinate where the top window begins (its bottom edge).
    public var dividerPosition: CGFloat {
        switch orientation {
        case .horizontal:
            return visibleFrame.origin.x + (visibleFrame.width * ratio)
        case .vertical:
            return visibleFrame.origin.y + (visibleFrame.height * (1.0 - ratio))
        }
    }

    public var dividerX: CGFloat { dividerPosition }
    public var dividerY: CGFloat { dividerPosition }

    /// Checks if both windows in the pair remain open and accessible in the system.
    public var isValid: Bool {
        return firstWindow.axFrame != nil && secondWindow.axFrame != nil
    }

    /// Frame of the interactive divider handle window.
    public var dividerFrame: CGRect {
        let handleBreadth: CGFloat = 24.0
        switch orientation {
        case .horizontal:
            return CGRect(
                x: dividerPosition - (handleBreadth / 2.0),
                y: visibleFrame.origin.y,
                width: handleBreadth,
                height: visibleFrame.height
            )
        case .vertical:
            return CGRect(
                x: visibleFrame.origin.x,
                y: dividerPosition - (handleBreadth / 2.0),
                width: visibleFrame.width,
                height: handleBreadth
            )
        }
    }

    /// Applies current split ratios to both windows using directional anti-collision ordering,
    /// ensuring shrinking windows release screen space before expanding windows resize.
    @discardableResult
    public func applyCurrentSplit(primaryScreenHeight: CGFloat) -> Bool {
        let (firstRect, secondRect) = calculateFrames()
        guard primaryScreenHeight.isFinite && primaryScreenHeight > 0,
              firstWindow.isResizable, secondWindow.isResizable,
              validFrame(firstRect), validFrame(secondRect),
              let currentFirst = firstWindow.cocoaFrame(primaryScreenHeight: primaryScreenHeight),
              let currentSecond = secondWindow.cocoaFrame(primaryScreenHeight: primaryScreenHeight),
              validFrame(currentFirst), validFrame(currentSecond) else { return false }

        let firstIsExpanding = orientation == .horizontal
            ? firstRect.width > currentFirst.width
            : firstRect.height > currentFirst.height
        if firstIsExpanding {
            // Do not expand into space that the other application refused to release.
            guard secondWindow.setCocoaFrame(secondRect, primaryScreenHeight: primaryScreenHeight) else { return false }
            return firstWindow.setCocoaFrame(firstRect, primaryScreenHeight: primaryScreenHeight)
        }
        guard firstWindow.setCocoaFrame(firstRect, primaryScreenHeight: primaryScreenHeight) else { return false }
        return secondWindow.setCocoaFrame(secondRect, primaryScreenHeight: primaryScreenHeight)
    }

    private func validFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite &&
            frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }

    /// Updates only the split ratio based on cursor drag with gentle magnetic snapping,
    /// without triggering live AX window resizes to prevent third-party app stutter.
    public func updateRatioOnly(from cursorCoordinate: CGFloat) {
        var rawRatio: CGFloat

        switch orientation {
        case .horizontal:
            let relativeX = cursorCoordinate - visibleFrame.origin.x
            rawRatio = relativeX / visibleFrame.width
        case .vertical:
            let relativeY = cursorCoordinate - visibleFrame.origin.y
            let bottomRatio = relativeY / visibleFrame.height
            rawRatio = 1.0 - bottomRatio
        }

        self.ratio = applyMagneticSnap(rawRatio)
    }

    /// Updates the split ratio based on cursor drag with gentle magnetic snapping.
    public func updateRatioFromCursor(cursorCoordinate: CGFloat, primaryScreenHeight: CGFloat) {
        updateRatioOnly(from: cursorCoordinate)
        applyCurrentSplit(primaryScreenHeight: primaryScreenHeight)
    }

    /// Preserves compatibility with previous horizontal callers.
    public func updateRatioFromDividerX(_ currentX: CGFloat, primaryScreenHeight: CGFloat) {
        updateRatioFromCursor(cursorCoordinate: currentX, primaryScreenHeight: primaryScreenHeight)
    }

    /// Gentle magnetic snapping at 50/50 (0.5), 33/67 (0.333) and 67/33 (0.667).
    private func applyMagneticSnap(_ raw: CGFloat) -> CGFloat {
        let magneticTolerance: CGFloat = 0.035 // 3.5% magnetic snap reach

        if abs(raw - 0.50) <= magneticTolerance {
            return 0.50
        } else if abs(raw - (1.0 / 3.0)) <= magneticTolerance {
            return 1.0 / 3.0
        } else if abs(raw - (2.0 / 3.0)) <= magneticTolerance {
            return 2.0 / 3.0
        }
        return raw
    }
}
