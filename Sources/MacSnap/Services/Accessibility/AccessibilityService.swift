import Foundation
import ApplicationServices
import CoreGraphics
import Cocoa

/// Robust implementation of communication with the Apple Accessibility API,
/// with multi-level fallback support for capturing target windows even during active drags
/// or when MacSnap panels/menus are frontmost.
public final class AccessibilityService: AccessibilityServiceProtocol, @unchecked Sendable {
    public static let shared = AccessibilityService()

    private var lastActiveApp: NSRunningApplication?

    public init() {
        // Observes application activation to track the user's frontmost application
        // even when interacting with the MacSnap status bar menu
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let myPid = ProcessInfo.processInfo.processIdentifier
            if app.processIdentifier != myPid && app.activationPolicy == .regular {
                self?.lastActiveApp = app
            }
        }
    }

    public func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Obtains the frontmost window using 5 levels of fault tolerance.
    public func getFocusedWindow() -> WindowElement? {
        let myPid = ProcessInfo.processInfo.processIdentifier

        // 1. Attempt to get frontmost application via Accessibility API
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedAppValue: CFTypeRef?
        var targetAppElement: AXUIElement?
        var targetPid: pid_t = 0

        if AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute as CFString, &focusedAppValue) == .success,
           let appVal = focusedAppValue {
            let app = appVal as! AXUIElement
            var pid: pid_t = 0
            AXUIElementGetPid(app, &pid)

            // If the focused application is not MacSnap itself, use it
            if pid != myPid && pid != 0 {
                targetAppElement = app
                targetPid = pid
            }
        }

        // 2. If the focused app is MacSnap (e.g. status bar menu is open),
        // fallback to the last registered active regular application
        if targetAppElement == nil, let lastApp = lastActiveApp, !lastApp.isTerminated, lastApp.processIdentifier != myPid {
            targetPid = lastApp.processIdentifier
            targetAppElement = AXUIElementCreateApplication(targetPid)
        }

        // 3. Query NSWorkspace for the user's active frontmost application
        if targetAppElement == nil {
            let candidateApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.isActive && $0.processIdentifier != myPid && $0.activationPolicy == .regular
            }) ?? NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication

            if let validApp = candidateApp, validApp.processIdentifier != myPid && validApp.activationPolicy == .regular {
                targetPid = validApp.processIdentifier
                targetAppElement = AXUIElementCreateApplication(targetPid)
            }
        }

        // 4. If target application was found, query its active window cascading:
        //    a) kAXFocusedWindowAttribute
        //    b) kAXMainWindowAttribute
        //    c) kAXWindowsAttribute (first valid window)
        if let appElement = targetAppElement {
            if let window = extractWindow(from: appElement, pid: targetPid) {
                return window
            }
        }

        // 5. Query the global WindowServer window list (CGWindowList) for the topmost
        // level 0 (normal) window on screen that does not belong to MacSnap
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for win in windowList {
            let layer = win[kCGWindowLayer as String] as? Int ?? -1
            let pid = win[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let bounds = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let w = bounds["Width"] as? Double ?? 0
            let h = bounds["Height"] as? Double ?? 0

            if layer == 0 && pid != myPid && pid != 0 && w > 120 && h > 100 {
                let app = AXUIElementCreateApplication(pid)
                if let win = extractWindow(from: app, pid: pid) {
                    return win
                }
            }
        }

        // 6. Final fallback: attempt to find the window directly under cursor position
        let mouseLocation = NSEvent.mouseLocation
        if let primaryScreen = NSScreen.screens.first {
            let axPoint = ScreenGeometry.cocoaPointToAX(cocoaPoint: mouseLocation, primaryScreenHeight: primaryScreen.frame.height)
            if let windowUnderCursor = getWindowUnderPoint(axPoint), windowUnderCursor.pid != myPid {
                return windowUnderCursor
            }
        }

        return nil
    }

    /// Extracts a valid window from an application trying FocusedWindow -> MainWindow -> Windows[0].
    private func extractWindow(from appElement: AXUIElement, pid: pid_t) -> WindowElement? {
        // Attempt A: Focused Window
        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
           let winVal = focusedWindowValue {
            return WindowElement(element: winVal as! AXUIElement, pid: pid)
        }

        // Attempt B: Main Window (common during title bar dragging)
        var mainWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowValue) == .success,
           let winVal = mainWindowValue {
            return WindowElement(element: winVal as! AXUIElement, pid: pid)
        }

        // Attempt C: Application window list
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let winArray = windowsValue as? [AXUIElement], let firstWin = winArray.first {
            return WindowElement(element: firstWin, pid: pid)
        }

        return nil
    }

    public func getWindowUnderPoint(_ point: CGPoint) -> WindowElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var elementUnderCursor: AXUIElement?

        let result = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &elementUnderCursor
        )

        guard result == .success, let element = elementUnderCursor else {
            return nil
        }

        // If the element is not a window (could be button, text, etc.),
        // traverse up the hierarchy until reaching the parent window (kAXWindowRole)
        var current: AXUIElement = element
        while true {
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String, role == (kAXWindowRole as String) {
                var pid: pid_t = 0
                AXUIElementGetPid(current, &pid)
                return WindowElement(element: current, pid: pid)
            }

            var parentValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
               let parent = parentValue {
                current = (parent as! AXUIElement)
            } else {
                break
            }
        }

        return nil
    }
}
