import CoreGraphics

/// Reported outer-window bounds. Absence means unknown, rather than unrestricted.
struct WindowSizeLimits: Sendable {
    var minimum: CGSize?
    var maximum: CGSize?

    init(minimum: CGSize? = nil, maximum: CGSize? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }

    private var isValid: Bool {
        for size in [minimum, maximum].compactMap({ $0 }) {
            guard size.width.isFinite, size.height.isFinite,
                  size.width >= 0, size.height >= 0 else { return false }
        }
        if let maximum, maximum.width <= 0 || maximum.height <= 0 { return false }
        if let minimum, let maximum,
           minimum.width > maximum.width || minimum.height > maximum.height { return false }
        return true
    }

    /// Fits known bounds and retains the requested screen edge or center.
    /// Impossible or inconsistent bounds must not produce an out-of-screen placement.
    func fitting(_ target: CGRect, within screen: CGRect) -> CGRect? {
        guard isValid, AXWindowFrameAccess.isUsable(target), AXWindowFrameAccess.isUsable(screen) else { return nil }
        let width = min(max(target.width, minimum?.width ?? 0), maximum?.width ?? .greatestFiniteMagnitude)
        let height = min(max(target.height, minimum?.height ?? 0), maximum?.height ?? .greatestFiniteMagnitude)
        guard width <= screen.width, height <= screen.height else { return nil }
        // Preserve an already valid target exactly when no size adjustment is needed.
        // Reconstructing its center can introduce rounding drift (notably thirds).
        if width == target.width, height == target.height, screen.contains(target) { return target }
        func origin(_ low: CGFloat, _ high: CGFloat, _ screenLow: CGFloat, _ screenHigh: CGFloat, _ length: CGFloat) -> CGFloat {
            let atLow = abs(low - screenLow) < 1
            let atHigh = abs(high - screenHigh) < 1
            let anchored = atLow == atHigh ? (low + high - length) / 2 : (atLow ? low : high - length)
            return min(max(anchored, screenLow), screenHigh - length)
        }
        return CGRect(x: origin(target.minX, target.maxX, screen.minX, screen.maxX, width),
                      y: origin(target.minY, target.maxY, screen.minY, screen.maxY, height),
                      width: width, height: height)
    }
}
