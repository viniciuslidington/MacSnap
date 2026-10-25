import Foundation
import CoreGraphics
import Cocoa

/// Utilitários para conversão e manipulação geométrica entre
/// o sistema de coordenadas do Cocoa (origem no canto inferior esquerdo)
/// e o sistema de coordenadas da Accessibility API (origem no canto superior esquerdo).
public struct ScreenGeometry {

    /// Converte um retângulo do sistema Cocoa para o sistema de coordenadas da Accessibility API.
    /// - Parameters:
    ///   - cocoaRect: Retângulo em coordenadas Cocoa.
    ///   - primaryScreenHeight: Altura total da tela primária (NSScreen.screens.first?.frame.height).
    /// - Returns: Retângulo formatado para a Accessibility API (AXUIElement).
    public static func cocoaToAX(cocoaRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let axX = cocoaRect.origin.x
        let axY = primaryScreenHeight - (cocoaRect.origin.y + cocoaRect.height)
        return CGRect(x: axX, y: axY, width: cocoaRect.width, height: cocoaRect.height)
    }

    /// Converte um retângulo da Accessibility API para o sistema Cocoa.
    /// - Parameters:
    ///   - axRect: Retângulo em coordenadas Accessibility.
    ///   - primaryScreenHeight: Altura total da tela primária.
    /// - Returns: Retângulo formatado para o Cocoa (NSScreen, NSWindow).
    public static func axToCocoa(axRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let cocoaX = axRect.origin.x
        let cocoaY = primaryScreenHeight - (axRect.origin.y + axRect.height)
        return CGRect(x: cocoaX, y: cocoaY, width: axRect.width, height: axRect.height)
    }

    /// Converte um ponto da Accessibility API para o sistema Cocoa.
    public static func axPointToCocoa(axPoint: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        return CGPoint(x: axPoint.x, y: primaryScreenHeight - axPoint.y)
    }

    /// Converte um ponto do Cocoa para a Accessibility API.
    public static func cocoaPointToAX(cocoaPoint: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        return CGPoint(x: cocoaPoint.x, y: primaryScreenHeight - cocoaPoint.y)
    }
}
