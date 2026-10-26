import Foundation
import CoreGraphics
import Cocoa

/// Orientação da divisão entre as duas janelas emparelhadas.
public enum SplitOrientation: Sendable {
    case horizontal // Janelas lado a lado (Esquerda e Direita)
    case vertical   // Janelas empilhadas (Topo e Base, essencial para monitores verticais)
}

/// Representa um par de janelas emparelhadas (estilo Windows Snap Assist).
/// Suporta tanto divisões horizontais (Esquerda/Direita) quanto verticais (Topo/Base),
/// com atração magnética em proporções comuns e prevenção dinâmica de sobreposição.
public final class PairedSplit: @unchecked Sendable {
    public let firstWindow: WindowElement   // Janela da Esquerda ou do Topo
    public let secondWindow: WindowElement  // Janela da Direita ou da Base
    public let orientation: SplitOrientation
    public var visibleFrame: CGRect

    /// Proporção do espaço ocupado pela primeira janela (entre 0.15 e 0.85).
    /// - Para horizontal: proporção da largura da janela esquerda.
    /// - Para vertical: proporção da altura da janela do topo.
    public var ratio: CGFloat {
        didSet {
            ratio = min(max(ratio, 0.15), 0.85)
        }
    }

    public init(
        firstWindow: WindowElement,
        secondWindow: WindowElement,
        orientation: SplitOrientation = .horizontal,
        visibleFrame: CGRect,
        ratio: CGFloat = 0.5
    ) {
        self.firstWindow = firstWindow
        self.secondWindow = secondWindow
        self.orientation = orientation
        self.visibleFrame = visibleFrame
        self.ratio = min(max(ratio, 0.15), 0.85)
    }

    // Compatibilidade com inicializador anterior (left/right)
    public convenience init(
        leftWindow: WindowElement,
        rightWindow: WindowElement,
        visibleFrame: CGRect,
        ratio: CGFloat = 0.5
    ) {
        self.init(
            firstWindow: leftWindow,
            secondWindow: rightWindow,
            orientation: .horizontal,
            visibleFrame: visibleFrame,
            ratio: ratio
        )
    }

    public var leftWindow: WindowElement { firstWindow }
    public var rightWindow: WindowElement { secondWindow }
    public var topWindow: WindowElement { firstWindow }
    public var bottomWindow: WindowElement { secondWindow }

    /// Calcula os retângulos em coordenadas Cocoa para a primeira e segunda janela.
    public func calculateFrames() -> (first: CGRect, second: CGRect) {
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let width = visibleFrame.width
        let height = visibleFrame.height

        switch orientation {
        case .horizontal:
            let leftWidth = (width * ratio).rounded()
            let rightWidth = width - leftWidth
            let leftRect = CGRect(x: x, y: y, width: leftWidth, height: height)
            let rightRect = CGRect(x: x + leftWidth, y: y, width: rightWidth, height: height)
            return (leftRect, rightRect)

        case .vertical:
            let bottomHeight = (height * (1.0 - ratio)).rounded()
            let topHeight = height - bottomHeight
            // No Cocoa, a janela da base começa em y, e a do topo começa em y + bottomHeight
            let bottomRect = CGRect(x: x, y: y, width: width, height: bottomHeight)
            let topRect = CGRect(x: x, y: y + bottomHeight, width: width, height: topHeight)
            return (topRect, bottomRect)
        }
    }

    /// Posição exata do divisor central baseada na borda real alcançada pela primeira janela:
    /// - Se horizontal, retorna a coordenada X onde a janela da esquerda termina.
    /// - Se vertical, retorna a coordenada Y onde a janela do topo começa (borda inferior dela).
    public var dividerPosition: CGFloat {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        switch orientation {
        case .horizontal:
            if let actualFirst = firstWindow.cocoaFrame(primaryScreenHeight: primaryHeight) {
                return actualFirst.maxX
            }
            return visibleFrame.origin.x + (visibleFrame.width * ratio)
        case .vertical:
            if let actualFirst = firstWindow.cocoaFrame(primaryScreenHeight: primaryHeight) {
                return actualFirst.minY
            }
            return visibleFrame.origin.y + (visibleFrame.height * (1.0 - ratio))
        }
    }

    public var dividerX: CGFloat { dividerPosition }
    public var dividerY: CGFloat { dividerPosition }

    /// Verifica se ambas as janelas do par continuam abertas e acessíveis no sistema.
    public var isValid: Bool {
        return firstWindow.axFrame != nil && secondWindow.axFrame != nil
    }

    /// Retângulo do divisor para posicionar a janela de manuseio.
    public var dividerFrame: CGRect {
        let handleBreadth: CGFloat = 24.0
        switch orientation {
        case .horizontal:
            return CGRect(
                x: dividerPosition - (handleBreadth / 2.0),
                y: visibleFrame.origin.y,
                width: handleBreadth,
                height: visibleFrame.height
            )
        case .vertical:
            return CGRect(
                x: visibleFrame.origin.x,
                y: dividerPosition - (handleBreadth / 2.0),
                width: visibleFrame.width,
                height: handleBreadth
            )
        }
    }

    /// Aplica as proporções atuais às duas janelas garantindo que NUNCA haja sobreposição,
    /// mesmo quando um aplicativo (como o Xcode) possuir restrição de altura mínima.
    public func applyCurrentSplit(primaryScreenHeight: CGFloat) {
        let (firstRect, secondRect) = calculateFrames()
        switch orientation {
        case .horizontal:
            firstWindow.setCocoaFrame(firstRect, primaryScreenHeight: primaryScreenHeight)
            if let actualFirst = firstWindow.cocoaFrame(primaryScreenHeight: primaryScreenHeight) {
                let actualLeftW = actualFirst.width
                let remainingW = max(visibleFrame.width - actualLeftW, 100)
                let adjustedSecond = CGRect(
                    x: visibleFrame.origin.x + actualLeftW,
                    y: visibleFrame.origin.y,
                    width: remainingW,
                    height: visibleFrame.height
                )
                secondWindow.setCocoaFrame(adjustedSecond, primaryScreenHeight: primaryScreenHeight)
            } else {
                secondWindow.setCocoaFrame(secondRect, primaryScreenHeight: primaryScreenHeight)
            }

        case .vertical:
            firstWindow.setCocoaFrame(firstRect, primaryScreenHeight: primaryScreenHeight)
            if let actualTop = firstWindow.cocoaFrame(primaryScreenHeight: primaryScreenHeight) {
                // actualTop.minY é a borda inferior real da janela superior (Xcode)
                let actualBottomHeight = max(actualTop.minY - visibleFrame.origin.y, 100)
                let adjustedBottom = CGRect(
                    x: visibleFrame.origin.x,
                    y: visibleFrame.origin.y,
                    width: visibleFrame.width,
                    height: actualBottomHeight
                )
                secondWindow.setCocoaFrame(adjustedBottom, primaryScreenHeight: primaryScreenHeight)
            } else {
                secondWindow.setCocoaFrame(secondRect, primaryScreenHeight: primaryScreenHeight)
            }
        }
    }

    /// Atualiza a proporção com base no arraste do cursor com atração magnética suave.
    public func updateRatioFromCursor(cursorCoordinate: CGFloat, primaryScreenHeight: CGFloat) {
        var rawRatio: CGFloat

        switch orientation {
        case .horizontal:
            let relativeX = cursorCoordinate - visibleFrame.origin.x
            rawRatio = relativeX / visibleFrame.width
        case .vertical:
            let relativeY = cursorCoordinate - visibleFrame.origin.y
            let bottomRatio = relativeY / visibleFrame.height
            rawRatio = 1.0 - bottomRatio
        }

        self.ratio = applyMagneticSnap(rawRatio)
        applyCurrentSplit(primaryScreenHeight: primaryScreenHeight)
    }

    /// Mantém compatibilidade com chamadas horizontais anteriores.
    public func updateRatioFromDividerX(_ currentX: CGFloat, primaryScreenHeight: CGFloat) {
        updateRatioFromCursor(cursorCoordinate: currentX, primaryScreenHeight: primaryScreenHeight)
    }

    /// Atração magnética suave em 50/50 (0.5), 33/67 (0.333) e 67/33 (0.667).
    private func applyMagneticSnap(_ raw: CGFloat) -> CGFloat {
        let magneticTolerance: CGFloat = 0.035 // 3.5% de alcance magnético

        if abs(raw - 0.50) <= magneticTolerance {
            return 0.50
        } else if abs(raw - (1.0 / 3.0)) <= magneticTolerance {
            return 1.0 / 3.0
        } else if abs(raw - (2.0 / 3.0)) <= magneticTolerance {
            return 2.0 / 3.0
        }
        return raw
    }
}
