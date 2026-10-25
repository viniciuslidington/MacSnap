import Foundation
import CoreGraphics

/// Representa as possíveis zonas de ancoragem (snap) na tela,
/// similar ao funcionamento do Windows Snap (Aero Snap e Snap Layouts).
public enum SnapZone: Sendable, Equatable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
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

        case .centerThird:
            let thirdWidth = width / 3.0
            return CGRect(x: x + thirdWidth, y: y, width: thirdWidth, height: height)
        }
    }
}
