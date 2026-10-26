import Foundation
import CoreGraphics

/// Representa as possíveis zonas de ancoragem (snap) na tela,
/// incluindo suporte avançado para layouts simétricos e assimétricos (2/3 e 1/3).
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

    // Colunas Horizontais (Especial para Telas 16:9 / Ultrawide)
    case leftThird
    case centerThird
    case rightThird

    // Layouts Horizontais Assimétricos (2/3 e 1/3 e inverso)
    case leftTwoThirds    // Esquerda 2/3
    case rightOneThird    // Direita 1/3 (parceira de leftTwoThirds)
    case leftOneThird     // Esquerda 1/3 (mesmo que leftThird)
    case rightTwoThirds   // Direita 2/3 (parceira de leftOneThird)

    // Partições Verticais (Especial para Monitores Verticais / Portrait)
    case topThird         // Topo 1/3
    case middleThird      // Centro 1/3
    case bottomThird      // Base 1/3
    case topTwoThirds     // Topo 2/3 (parceira de bottomThird)
    case bottomTwoThirds  // Base 2/3 (parceira de topThird - inverso)

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

        let thirdWidth = width / 3.0
        let twoThirdsWidth = width * (2.0 / 3.0)

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

        // Quadrantes
        case .topLeftQuarter:
            return CGRect(x: x, y: y + halfHeight, width: halfWidth, height: halfHeight)

        case .topRightQuarter:
            return CGRect(x: x + halfWidth, y: y + halfHeight, width: halfWidth, height: halfHeight)

        case .bottomLeftQuarter:
            return CGRect(x: x, y: y, width: halfWidth, height: halfHeight)

        case .bottomRightQuarter:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: halfHeight)

        // Colunas e Terços Horizontais (16:9 / Ultrawide)
        case .leftThird, .leftOneThird:
            return CGRect(x: x, y: y, width: thirdWidth, height: height)

        case .centerThird:
            return CGRect(x: x + thirdWidth, y: y, width: thirdWidth, height: height)

        case .rightThird, .rightOneThird:
            return CGRect(x: x + twoThirdsWidth, y: y, width: thirdWidth, height: height)

        // Assimétricos Horizontais (2/3 e 1/3)
        case .leftTwoThirds:
            return CGRect(x: x, y: y, width: twoThirdsWidth, height: height)

        case .rightTwoThirds:
            return CGRect(x: x + thirdWidth, y: y, width: twoThirdsWidth, height: height)

        // Partições Verticais (Monitores Verticais)
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
        }
    }
}
