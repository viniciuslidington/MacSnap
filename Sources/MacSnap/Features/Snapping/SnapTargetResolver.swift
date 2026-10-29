import Cocoa

/// The same intent is interpreted for preview and placement. Native observations may refresh.
public enum SnapIntent: Sendable {
    case exactSlot
    case adaptive
}

@MainActor
enum SnapTargetResolver {
    static func targetRect(
        for zone: SnapZone, window: WindowElement, visibleFrame: CGRect,
        primaryScreenHeight: CGFloat, intent: SnapIntent, discovery: any WindowDiscovering
    ) -> CGRect {
        let target = zone.targetRect(for: visibleFrame)
        guard intent == .adaptive, visibleFrame.width > 0, visibleFrame.height > 0 else { return target }
        func frame(at point: CGPoint) -> CGRect? {
            guard let candidate = discovery.window(atCocoaPoint: point, excluding: window, primaryScreenHeight: primaryScreenHeight),
                  !candidate.isSameWindow(as: window) else { return nil }
            return candidate.cocoaFrame(primaryScreenHeight: primaryScreenHeight)
        }
        var proposed: CGRect?
        switch zone {
        case .bottomHalf, .bottomThird, .bottomTwoThirds:
            let point = CGPoint(x: target.midX, y: min(target.maxY + 30, visibleFrame.maxY - 20))
            if let other = frame(at: point), abs(other.maxY - visibleFrame.maxY) <= 40,
               other.minY <= target.maxY + 40, other.minY - visibleFrame.minY >= 80 {
                proposed = CGRect(x: target.minX, y: visibleFrame.minY, width: target.width, height: other.minY - visibleFrame.minY)
            }
        case .topHalf, .topThird, .topTwoThirds:
            let point = CGPoint(x: target.midX, y: max(target.minY - 30, visibleFrame.minY + 20))
            if let other = frame(at: point), abs(other.minY - visibleFrame.minY) <= 40,
               other.maxY >= target.minY - 40, visibleFrame.maxY - other.maxY >= 80 {
                proposed = CGRect(x: target.minX, y: other.maxY, width: target.width, height: visibleFrame.maxY - other.maxY)
            }
        case .rightHalf, .rightOneThird, .rightThird, .rightTwoThirds:
            let point = CGPoint(x: max(target.minX - 30, visibleFrame.minX + 20), y: target.midY)
            if let other = frame(at: point), abs(other.minX - visibleFrame.minX) <= 40,
               other.maxX >= target.minX - 40, visibleFrame.maxX - other.maxX >= 100 {
                proposed = CGRect(x: other.maxX, y: target.minY, width: visibleFrame.maxX - other.maxX, height: target.height)
            }
        case .leftHalf, .leftOneThird, .leftThird, .leftTwoThirds:
            let point = CGPoint(x: min(target.maxX + 30, visibleFrame.maxX - 20), y: target.midY)
            if let other = frame(at: point), abs(other.maxX - visibleFrame.maxX) <= 40,
               other.minX <= target.maxX + 40, other.minX - visibleFrame.minX >= 100 {
                proposed = CGRect(x: visibleFrame.minX, y: target.minY, width: other.minX - visibleFrame.minX, height: target.height)
            }
        case .centerThird:
            let left = frame(at: CGPoint(x: max(target.minX - 30, visibleFrame.minX + 20), y: target.midY))
            let right = frame(at: CGPoint(x: min(target.maxX + 30, visibleFrame.maxX - 20), y: target.midY))
            let leftEdge = left.flatMap { abs($0.minX - visibleFrame.minX) <= 40 ? $0.maxX : nil } ?? target.minX
            let rightEdge = right.flatMap { abs($0.maxX - visibleFrame.maxX) <= 40 ? $0.minX : nil } ?? target.maxX
            if rightEdge - leftEdge >= 100 {
                proposed = CGRect(x: leftEdge, y: target.minY, width: rightEdge - leftEdge, height: target.height)
            }
        default:
            break
        }
        guard let proposed, proposed.width.isFinite, proposed.height.isFinite,
              proposed.width > 0, proposed.height > 0,
              visibleFrame.insetBy(dx: -1, dy: -1).contains(proposed) else { return target }
        return proposed
    }
}
