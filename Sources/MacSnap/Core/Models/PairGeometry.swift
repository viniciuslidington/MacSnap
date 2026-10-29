import CoreGraphics

/// Admission geometry matches what a full-display binary split can actually resize.
enum PairGeometry {
    static func split(first: CGRect, second: CGRect, in visible: CGRect, gapTolerance: CGFloat = 32, edgeTolerance: CGFloat = 50)
        -> (orientation: SplitOrientation, firstIsLeading: Bool, ratio: CGFloat)? {
        guard visible.width > 0, visible.height > 0,
              first.width > 50, first.height > 50, second.width > 50, second.height > 50 else { return nil }
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= edgeTolerance }
        let leftFirst = first.minX <= second.minX
        let left = leftFirst ? first : second
        let right = leftFirst ? second : first
        if abs(left.maxX - right.minX) <= gapTolerance,
           near(left.minX, visible.minX), near(right.maxX, visible.maxX),
           near(left.minY, visible.minY), near(left.maxY, visible.maxY),
           near(right.minY, visible.minY), near(right.maxY, visible.maxY) {
            let ratio = (left.maxX - visible.minX) / visible.width
            guard ratio >= 0.15 - 1 / visible.width, ratio <= 0.85 + 1 / visible.width else { return nil }
            return (.horizontal, leftFirst, min(max(ratio, 0.15), 0.85))
        }
        let topFirst = first.maxY >= second.maxY
        let top = topFirst ? first : second
        let bottom = topFirst ? second : first
        if abs(top.minY - bottom.maxY) <= gapTolerance,
           near(top.maxY, visible.maxY), near(bottom.minY, visible.minY),
           near(top.minX, visible.minX), near(top.maxX, visible.maxX),
           near(bottom.minX, visible.minX), near(bottom.maxX, visible.maxX) {
            let ratio = (visible.maxY - top.minY) / visible.height
            guard ratio >= 0.15 - 1 / visible.height, ratio <= 0.85 + 1 / visible.height else { return nil }
            return (.vertical, topFirst, min(max(ratio, 0.15), 0.85))
        }
        return nil
    }
}
