import Foundation
import ApplicationServices
import CoreGraphics
import Cocoa

/// Implementação robusta do serviço de comunicação com a Accessibility API da Apple,
/// com suporte a fallback multinível para captura da janela alvo mesmo durante arraste
/// ou quando painéis/menus do próprio MacSnap estão em primeiro plano.
public final class AccessibilityService: AccessibilityServiceProtocol, @unchecked Sendable {
    public static let shared = AccessibilityService()

    public init() {}

    public func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Obtém a janela em primeiro plano com 4 níveis de tolerância a falhas.
    public func getFocusedWindow() -> WindowElement? {
        let myPid = ProcessInfo.processInfo.processIdentifier

        // 1. Tenta obter o app frontal via Accessibility API
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedAppValue: CFTypeRef?
        var targetAppElement: AXUIElement?
        var targetPid: pid_t = 0

        if AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute as CFString, &focusedAppValue) == .success,
           let appVal = focusedAppValue {
            let app = appVal as! AXUIElement
            var pid: pid_t = 0
            AXUIElementGetPid(app, &pid)

            // Se o app em foco NÃO for o próprio MacSnap, usamos ele
            if pid != myPid && pid != 0 {
                targetAppElement = app
                targetPid = pid
            }
        }

        // 2. Se o app em foco for o próprio MacSnap (ex: menu ou Snap Bar aberto) ou falhou,
        // consulta o NSWorkspace pelo aplicativo ativo real do usuário
        if targetAppElement == nil {
            let candidateApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.isActive && $0.processIdentifier != myPid && $0.activationPolicy == .regular
            }) ?? NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication

            if let validApp = candidateApp, validApp.processIdentifier != myPid {
                targetPid = validApp.processIdentifier
                targetAppElement = AXUIElementCreateApplication(targetPid)
            }
        }

        // 3. Se encontrou o aplicativo alvo, busca sua janela ativa usando estratégia em cascata:
        //    a) kAXFocusedWindowAttribute
        //    b) kAXMainWindowAttribute
        //    c) kAXWindowsAttribute (primeira janela válida)
        if let appElement = targetAppElement {
            if let window = extractWindow(from: appElement, pid: targetPid) {
                return window
            }
        }

        // 4. Último fallback: tenta encontrar a janela sob a posição atual do cursor
        let mouseLocation = NSEvent.mouseLocation
        if let primaryScreen = NSScreen.screens.first {
            let axPoint = ScreenGeometry.cocoaPointToAX(cocoaPoint: mouseLocation, primaryScreenHeight: primaryScreen.frame.height)
            if let windowUnderCursor = getWindowUnderPoint(axPoint), windowUnderCursor.pid != myPid {
                return windowUnderCursor
            }
        }

        return nil
    }

    /// Extrai uma janela válida de uma aplicação tentando FocusedWindow -> MainWindow -> Windows[0].
    private func extractWindow(from appElement: AXUIElement, pid: pid_t) -> WindowElement? {
        // Tentativa A: Focused Window
        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
           let winVal = focusedWindowValue {
            return WindowElement(element: winVal as! AXUIElement, pid: pid)
        }

        // Tentativa B: Main Window (muito comum durante arraste da barra de título)
        var mainWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowValue) == .success,
           let winVal = mainWindowValue {
            return WindowElement(element: winVal as! AXUIElement, pid: pid)
        }

        // Tentativa C: Lista de janelas abertas da aplicação
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
