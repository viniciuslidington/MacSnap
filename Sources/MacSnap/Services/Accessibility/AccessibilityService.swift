import Foundation
import ApplicationServices
import CoreGraphics
import Cocoa

/// Implementação concreta do serviço de comunicação com a Accessibility API da Apple.
public final class AccessibilityService: AccessibilityServiceProtocol, @unchecked Sendable {
    public static let shared = AccessibilityService()

    public init() {}

    public func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func getFocusedWindow() -> WindowElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedAppValue: CFTypeRef?

        // 1. Localiza a aplicação em primeiro plano
        let appResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppValue
        )

        guard appResult == .success, let appElement = focusedAppValue else {
            return nil
        }

        // Obtém o PID do aplicativo
        var pid: pid_t = 0
        AXUIElementGetPid(appElement as! AXUIElement, &pid)

        // 2. Localiza a janela em foco dentro da aplicação
        var focusedWindowValue: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement as! AXUIElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard windowResult == .success, let windowElement = focusedWindowValue else {
            return nil
        }

        return WindowElement(element: windowElement as! AXUIElement, pid: pid)
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

        // Se o elemento capturado não for uma janela (pode ser botão, texto, etc.),
        // subimos na hierarquia até achar a janela pai (kAXWindowRole)
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
