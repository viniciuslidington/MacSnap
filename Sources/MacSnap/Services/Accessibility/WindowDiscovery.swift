import Cocoa
import ApplicationServices

/// One normal on-screen window, expressed in Cocoa coordinates and front-to-back list order.
public struct WindowObservation: Sendable {
    public let windowID: CGWindowID
    public let pid: pid_t
    public let frame: CGRect

    public init(windowID: CGWindowID, pid: pid_t, frame: CGRect) {
        self.windowID = windowID
        self.pid = pid
        self.frame = frame
    }
}

/// A short-lived observation. Resolution is cached within this observation, never across gestures.
/// WindowServer and AX are separate observations; this does not claim an atomic system snapshot.
@MainActor
public final class WindowSnapshot {
    public let windows: [WindowObservation]
    private let resolver: (WindowObservation) -> WindowElement?
    private var resolved: [CGWindowID: WindowElement] = [:]
    private var unresolved: Set<CGWindowID> = []

    public init(windows: [WindowObservation], resolver: @escaping (WindowObservation) -> WindowElement?) {
        self.windows = windows
        self.resolver = resolver
    }

    public func element(for observation: WindowObservation) -> WindowElement? {
        guard let observed = windows.first(where: { $0.windowID == observation.windowID && $0.pid == observation.pid }) else { return nil }
        if let cached = resolved[observation.windowID] { return cached }
        guard !unresolved.contains(observation.windowID) else { return nil }
        guard let element = resolver(observed), element.pid == observation.pid,
              !resolved.values.contains(where: { $0.isSameWindow(as: element) }) else {
            unresolved.insert(observation.windowID)
            return nil
        }
        resolved[observation.windowID] = element
        return element
    }

    public func isOccluded(at point: CGPoint, pairedFirst: WindowElement, pairedSecond: WindowElement) -> Bool {
        guard let frontmost = windows.first(where: { $0.frame.insetBy(dx: -4, dy: -4).contains(point) }) else { return false }
        // Unknown windows must not make an interactive divider cover an unrelated app.
        guard let element = element(for: frontmost) else { return true }
        return !element.isSameWindow(as: pairedFirst) && !element.isSameWindow(as: pairedSecond)
    }
}

@MainActor
public protocol WindowDiscovering {
    /// nil means unavailable, while an empty snapshot is a successful observation of no windows.
    func snapshot(primaryScreenHeight: CGFloat) -> WindowSnapshot?
    func window(atCocoaPoint point: CGPoint, excluding: WindowElement?, primaryScreenHeight: CGFloat) -> WindowElement?
}

/// Concentrates native window enumeration, ordering, conversion and element reconciliation.
@MainActor
public final class NativeWindowDiscovery: WindowDiscovering {
    public static let shared = NativeWindowDiscovery()
    private let accessibilityService: any AccessibilityServiceProtocol
    private let currentProcessID: pid_t
    private let windowInfo: () -> [[String: Any]]?
    private let applicationWindows: (pid_t) -> [WindowElement]

    public init(
        accessibilityService: any AccessibilityServiceProtocol = AccessibilityService.shared,
        currentProcessID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.accessibilityService = accessibilityService
        self.currentProcessID = currentProcessID
        self.windowInfo = {
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        }
        self.applicationWindows = NativeObservationResolver.windows(for:)
    }

    /// Observation adapters used by deterministic tests, without making them caller configuration.
    init(
        accessibilityService: any AccessibilityServiceProtocol,
        currentProcessID: pid_t,
        windowInfo: @escaping () -> [[String: Any]]?,
        applicationWindows: @escaping (pid_t) -> [WindowElement]
    ) {
        self.accessibilityService = accessibilityService
        self.currentProcessID = currentProcessID
        self.windowInfo = windowInfo
        self.applicationWindows = applicationWindows
    }

    public func snapshot(primaryScreenHeight: CGFloat) -> WindowSnapshot? {
        guard primaryScreenHeight.isFinite, primaryScreenHeight > 0,
              let info = windowInfo() else { return nil }
        let observations = info.compactMap { entry -> WindowObservation? in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  pid != 0, pid != currentProcessID,
                  let windowID = entry[kCGWindowNumber as String] as? CGWindowID, windowID != 0,
                  let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
                  let axFrame = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  AXWindowFrameAccess.isUsable(axFrame) else { return nil }
            let frame = ScreenGeometry.axToCocoa(axRect: axFrame, primaryScreenHeight: primaryScreenHeight)
            return WindowObservation(windowID: windowID, pid: pid, frame: frame)
        }
        let resolver = NativeObservationResolver(primaryScreenHeight: primaryScreenHeight, applicationWindows: applicationWindows)
        return WindowSnapshot(windows: observations) { observation in
            resolver.element(for: observation)
        }
    }

    public func window(atCocoaPoint point: CGPoint, excluding: WindowElement?, primaryScreenHeight: CGFloat) -> WindowElement? {
        guard point.x.isFinite, point.y.isFinite,
              primaryScreenHeight.isFinite, primaryScreenHeight > 0 else { return nil }
        let axPoint = ScreenGeometry.cocoaPointToAX(cocoaPoint: point, primaryScreenHeight: primaryScreenHeight)
        if let candidate = accessibilityService.getWindowUnderPoint(axPoint),
           candidate.pid != 0, candidate.pid != currentProcessID, !candidate.isDesktopWindow,
           candidate.cocoaFrame(primaryScreenHeight: primaryScreenHeight)?.insetBy(dx: -4, dy: -4).contains(point) == true,
           excluding.map({ !candidate.isSameWindow(as: $0) }) ?? true {
            return candidate
        }
        // Hit testing may identify the excluded window or one of MacSnap's own panels.
        // AX window lists also include minimized/off-Space windows: only consider visible records.
        guard let excluding, excluding.pid != 0, excluding.pid != currentProcessID,
              let visible = snapshot(primaryScreenHeight: primaryScreenHeight) else { return nil }
        for observation in visible.windows where observation.pid == excluding.pid && observation.frame.contains(point) {
            if let candidate = visible.element(for: observation),
               !candidate.isSameWindow(as: excluding), !candidate.isDesktopWindow {
                return candidate
            }
        }
        return nil
    }
}

@MainActor
private final class NativeObservationResolver {
    private struct Candidate {
        let window: WindowElement
        let frame: CGRect
    }
    private let primaryScreenHeight: CGFloat
    private let applicationWindows: (pid_t) -> [WindowElement]
    private var candidatesByPID: [pid_t: [Candidate]] = [:]

    init(primaryScreenHeight: CGFloat, applicationWindows: @escaping (pid_t) -> [WindowElement]) {
        self.primaryScreenHeight = primaryScreenHeight
        self.applicationWindows = applicationWindows
    }

    func element(for observation: WindowObservation) -> WindowElement? {
        let candidates: [Candidate]
        if let cached = candidatesByPID[observation.pid] {
            candidates = cached
        } else {
            candidates = applicationWindows(observation.pid).compactMap { window in
                guard let frame = window.cocoaFrame(primaryScreenHeight: primaryScreenHeight) else { return nil }
                return Candidate(window: window, frame: frame)
            }
            candidatesByPID[observation.pid] = candidates
        }
        let matches = candidates.map { candidate in
            (candidate.window, distance(candidate.frame, observation.frame))
        }.sorted { $0.1 < $1.1 }
        guard let closest = matches.first, closest.1 < 60 else { return nil }
        // Equal or near-equal geometries cannot establish individual window identity.
        if matches.count > 1, abs(matches[1].1 - closest.1) < 1 { return nil }
        return closest.0
    }

    private func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }

    static func windows(for pid: pid_t) -> [WindowElement] {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return AccessibilityService.elements(from: value).compactMap { element in
            var owner: pid_t = 0
            guard AXUIElementGetPid(element, &owner) == .success, owner == pid else { return nil }
            return WindowElement(element: element, pid: pid)
        }
    }
}
