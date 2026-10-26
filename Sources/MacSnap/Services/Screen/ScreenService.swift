import Foundation
import Cocoa
import CoreGraphics

/// Gerencia a descoberta de telas e os cálculos de dimensões e visibilidade de monitores.
public final class ScreenService: ScreenServiceProtocol, @unchecked Sendable {
    public static let shared = ScreenService()

    public init() {}

    public var screens: [NSScreen] {
        return NSScreen.screens
    }

    public var primaryScreen: NSScreen? {
        return NSScreen.screens.first
    }

    public var primaryScreenHeight: CGFloat {
        return primaryScreen?.frame.height ?? 0.0
    }

    public func screenContaining(point: CGPoint) -> NSScreen? {
        // No Cocoa, as telas estão posicionadas no mesmo espaço global onde o ponto do mouse reside
        return screens.first { $0.frame.contains(point) } ?? primaryScreen
    }

    public func screenContaining(rect: CGRect) -> NSScreen? {
        // Encontra a tela com maior sobreposição com o retângulo
        var bestScreen: NSScreen?
        var maxIntersectionArea: CGFloat = 0

        for screen in screens {
            let intersection = screen.frame.intersection(rect)
            let area = intersection.width * intersection.height
            if area > maxIntersectionArea {
                maxIntersectionArea = area
                bestScreen = screen
            }
        }

        return bestScreen ?? primaryScreen
    }
}

extension NSScreen {
    /// Indica se o monitor está posicionado na orientação vertical (altura maior que largura).
    public var isPortrait: Bool {
        return frame.height > frame.width
    }
}
