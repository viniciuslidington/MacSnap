import Foundation
import ApplicationServices
import CoreGraphics
import Cocoa

/// Encapsula uma janela do macOS obtida via Accessibility API (`AXUIElement`).
/// Fornece métodos seguros e tipados para consultar e alterar tamanho e posição.
public final class WindowElement: @unchecked Sendable, Identifiable {
    public let rawElement: AXUIElement
    public let pid: pid_t

    public init(element: AXUIElement, pid: pid_t) {
        self.rawElement = element
        self.pid = pid
    }

    /// Título da janela (ou nil se inacessível).
    public var title: String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(rawElement, kAXTitleAttribute as CFString, &value)
        guard result == .success, let titleStr = value as? String else { return nil }
        return titleStr
    }

    /// Obtém o retângulo da janela no sistema de coordenadas da Accessibility API.
    public var axFrame: CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(rawElement, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(rawElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posVal = posValue, let sizeVal = sizeValue else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero

        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

        return CGRect(origin: point, size: size)
    }

    /// Obtém o frame da janela convertido para coordenadas Cocoa.
    public func cocoaFrame(primaryScreenHeight: CGFloat) -> CGRect? {
        guard let axFrame = self.axFrame else { return nil }
        return ScreenGeometry.axToCocoa(axRect: axFrame, primaryScreenHeight: primaryScreenHeight)
    }

    /// Aplica nova posição e tamanho em coordenadas de Accessibility.
    /// - Parameters:
    ///   - newAXFrame: O CGRect em coordenadas AX.
    /// - Returns: Bool indicando se a alteração foi aceita pela janela.
    @discardableResult
    public func setAXFrame(_ newAXFrame: CGRect) -> Bool {
        var point = newAXFrame.origin
        var size = newAXFrame.size

        guard let posValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        // Tenta aplicar o tamanho primeiro para evitar colisão com a borda do monitor se a janela estiver encolhendo,
        // seguido pela nova posição.
        let sizeRes = AXUIElementSetAttributeValue(rawElement, kAXSizeAttribute as CFString, sizeValue)
        let posRes = AXUIElementSetAttributeValue(rawElement, kAXPositionAttribute as CFString, posValue)

        // Se falhou (por exemplo, a janela está crescendo e precisa ser movida antes de expandir), inverte a ordem
        if sizeRes != .success || posRes != .success {
            _ = AXUIElementSetAttributeValue(rawElement, kAXPositionAttribute as CFString, posValue)
            _ = AXUIElementSetAttributeValue(rawElement, kAXSizeAttribute as CFString, sizeValue)
        }

        return true
    }

    /// Aplica nova posição e tamanho usando coordenadas Cocoa (convertendo internamente).
    @discardableResult
    public func setCocoaFrame(_ cocoaRect: CGRect, primaryScreenHeight: CGFloat) -> Bool {
        let axFrame = ScreenGeometry.cocoaToAX(cocoaRect: cocoaRect, primaryScreenHeight: primaryScreenHeight)
        return setAXFrame(axFrame)
    }

    /// Verifica se a janela permite redimensionamento.
    public var isResizable: Bool {
        var isSettable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(rawElement, kAXSizeAttribute as CFString, &isSettable)
        return result == .success && isSettable.boolValue
    }
}
