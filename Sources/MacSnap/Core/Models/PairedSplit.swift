import Foundation
import CoreGraphics
import Cocoa

/// Representa um par de janelas emparelhadas lado a lado (estilo Windows Snap Assist).
/// Controla o divisor central e o cálculo simultâneo de redimensionamento de ambas as janelas.
public final class PairedSplit: @unchecked Sendable {
    public let leftWindow: WindowElement
    public let rightWindow: WindowElement
    public var visibleFrame: CGRect
    
    /// Proporção da largura ocupada pela janela esquerda (entre 0.15 e 0.85).
    /// Padrão é 0.5 (divisão 50/50).
    public var ratio: CGFloat {
        didSet {
            ratio = min(max(ratio, 0.15), 0.85)
        }
    }

    public init(leftWindow: WindowElement, rightWindow: WindowElement, visibleFrame: CGRect, ratio: CGFloat = 0.5) {
        self.leftWindow = leftWindow
        self.rightWindow = rightWindow
        self.visibleFrame = visibleFrame
        self.ratio = min(max(ratio, 0.15), 0.85)
    }

    /// Calcula os retângulos em coordenadas Cocoa para a janela da esquerda e da direita.
    public func calculateFrames() -> (left: CGRect, right: CGRect) {
        let totalWidth = visibleFrame.width
        let height = visibleFrame.height
        let y = visibleFrame.origin.y
        let startX = visibleFrame.origin.x

        let leftWidth = (totalWidth * ratio).rounded()
        let rightWidth = totalWidth - leftWidth

        let leftRect = CGRect(x: startX, y: y, width: leftWidth, height: height)
        let rightRect = CGRect(x: startX + leftWidth, y: y, width: rightWidth, height: height)

        return (leftRect, rightRect)
    }

    /// Posição X atual da linha divisória central em coordenadas Cocoa.
    public var dividerX: CGFloat {
        return visibleFrame.origin.x + (visibleFrame.width * ratio)
    }

    /// Atualiza as duas janelas simultaneamente com a proporção atual.
    public func applyCurrentSplit(primaryScreenHeight: CGFloat) {
        let (leftRect, rightRect) = calculateFrames()
        leftWindow.setCocoaFrame(leftRect, primaryScreenHeight: primaryScreenHeight)
        rightWindow.setCocoaFrame(rightRect, primaryScreenHeight: primaryScreenHeight)
    }

    /// Atualiza a proporção com base em uma nova coordenada X do cursor na tela.
    public func updateRatioFromDividerX(_ currentX: CGFloat, primaryScreenHeight: CGFloat) {
        let relativeX = currentX - visibleFrame.origin.x
        let newRatio = relativeX / visibleFrame.width
        self.ratio = newRatio
        applyCurrentSplit(primaryScreenHeight: primaryScreenHeight)
    }
}
