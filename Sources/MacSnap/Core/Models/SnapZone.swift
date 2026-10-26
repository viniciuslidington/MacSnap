import Foundation
import CoreGraphics

/// Representa as possíveis zonas de ancoragem (snap) na tela,
/// incluindo suporte avançado para monitores horizontais e verticais.
public enum SnapZone: Sendable, Equatable {
    // Layouts Padrão
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize

    // Quadrantes
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter

    // Terços Verticais (Especial para Monitores Verticais / Portrait)
    case topThird
    case middleThird
    case bottomThird
    case topTwoThirds
    case bottomTwoThirds

    // Terços Horizontais
    case centerThird

    /// Calcula o retângulo de destino (em coordenadas da tela Cocoa) para a zona indicada.
    /// - Parameter visibleFrame: O frame visível da tela (excluindo Dock e Menu bar).
    /// - Returns: O CGRect resultante para onde a janela deve ser redimensionada.
    public func targetRect(for visibleFrame: CGRect) -> CGRect {
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let width = visibleFrame.width
        let height = visibleFrame.height
        let halfWidth = width / 2.0
        let halfHeight = height / 2.0
        let thirdHeight = height / 3.0
        let twoThirdsHeight = height * (2.0 / 3.0)

        switch self {
        case .leftHalf:
            return CGRect(x: x, y: y, width: halfWidth, height: height)

        case .rightHalf:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: height)

        case .topHalf:
            return CGRect(x: x, y: y + halfHeight, width: width, height: halfHeight)

        case .bottomHalf:
            return CGRect(x: x, y: y, width: width, height: halfHeight)

        case .maximize:
            return visibleFrame

        case .topLeftQuarter:
            return CGRect(x: x, y: y + halfHeight, width: halfWidth, height: halfHeight)

        case .topRightQuarter:
            return CGRect(x: x + halfWidth, y: y + halfHeight, width: halfWidth, height: halfHeight)

        case .bottomLeftQuarter:
            return CGRect(x: x, y: y, width: halfWidth, height: halfHeight)

        case .bottomRightQuarter:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: halfHeight)

        // Monitores Verticais (Partições horizontais empilhadas)
        case .topThird:
            return CGRect(x: x, y: y + (thirdHeight * 2.0), width: width, height: thirdHeight)

        case .middleThird:
            return CGRect(x: x, y: y + thirdHeight, width: width, height: thirdHeight)

        case .bottomThird:
            return CGRect(x: x, y: y, width: width, height: thirdHeight)

        case .topTwoThirds:
            return CGRect(x: x, y: y + thirdHeight, width: width, height: twoThirdsHeight)

        case .bottomTwoThirds:
            return CGRect(x: x, y: y, width: width, height: twoThirdsHeight)

        case .centerThird:
            let thirdWidth = width / 3.0
            return CGRect(x: x + thirdWidth, y: y, width: thirdWidth, height: height)
        }
    }
}
