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

        // Multi-passo para garantir que o WindowServer não faça clamp:
        // No macOS, a ordem entre posição e tamanho é crucial:
        // Se aplicarmos tamanho primeiro enquanto a janela estiver em outra posição (ex: centro/canto da tela),
        // o WindowServer limita (clamp) o tamanho à borda visível da tela antes que a janela seja movida,
        // fazendo a janela ficar menor que a tela ("faltando um pedaço").
        // Aplicando posição -> tamanho -> posição -> tamanho garantimos que tanto janelas em expansão
        // quanto janelas em redução atinjam exatamente o frame alvo sem truncamento.

        // Passada 1: Move para a nova posição primeiro para desobstruir o espaço de expansão
        let posRes1 = AXUIElementSetAttributeValue(rawElement, kAXPositionAttribute as CFString, posValue)
        let sizeRes1 = AXUIElementSetAttributeValue(rawElement, kAXSizeAttribute as CFString, sizeValue)

        if posRes1 == .apiDisabled || sizeRes1 == .apiDisabled {
            print("[MacSnap] ❌ ERRO DE ACESSIBILIDADE: kAXErrorAPIDisabled ao tentar alterar a janela PID \(pid).")
            print("[MacSnap] 💡 Vá em Ajustes do Sistema > Privacidade e Segurança > Acessibilidade e habilite o MacSnap.")
            return false
        }

        // Passada 2: Aplica posição e tamanho novamente.
        // Se a janela estava encolhendo, a posição inicial pode ter sido clamped até o tamanho encolher;
        // agora que o tamanho foi reduzido, a posição atinge o alvo exato.
        // Se a janela estava crescendo, a posição inicial abriu o espaço e agora o tamanho atinge o alvo exato.
        _ = AXUIElementSetAttributeValue(rawElement, kAXPositionAttribute as CFString, posValue)
        _ = AXUIElementSetAttributeValue(rawElement, kAXSizeAttribute as CFString, sizeValue)

        // Passada 3 (Confirmação): se a janela divergir por mais de 4px, reforça a posição e tamanho finais.
        if let current = self.axFrame {
            let dw = abs(current.width - newAXFrame.width)
            let dh = abs(current.height - newAXFrame.height)
            let dx = abs(current.origin.x - newAXFrame.origin.x)
            let dy = abs(current.origin.y - newAXFrame.origin.y)

            if dw > 4 || dh > 4 || dx > 4 || dy > 4 {
                _ = AXUIElementSetAttributeValue(rawElement, kAXPositionAttribute as CFString, posValue)
                _ = AXUIElementSetAttributeValue(rawElement, kAXSizeAttribute as CFString, sizeValue)
            }
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
