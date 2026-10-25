import Foundation
import CoreGraphics
import Cocoa

/// Contrato para serviços que interagem com a Accessibility API do macOS.
public protocol AccessibilityServiceProtocol: Sendable {
    /// Verifica se a permissão de acessibilidade está habilitada nas preferências do macOS.
    /// - Parameter promptIfNeeded: Se true, exibe a caixa de diálogo do sistema pedindo autorização.
    func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool

    /// Obtém a janela atualmente focada pelo usuário.
    func getFocusedWindow() -> WindowElement?

    /// Obtém a janela localizada sob um ponto específico da tela (em coordenadas de Accessibility).
    func getWindowUnderPoint(_ point: CGPoint) -> WindowElement?
}

/// Contrato para gerenciamento de telas e cálculos de geometria de monitores.
public protocol ScreenServiceProtocol: Sendable {
    /// Todas as telas ativas no macOS.
    var screens: [NSScreen] { get }

    /// A tela primária do sistema (cujo canto inferior esquerdo é a origem 0,0 no Cocoa).
    var primaryScreen: NSScreen? { get }

    /// Altura da tela primária (necessária para conversão de coordenadas com Accessibility).
    var primaryScreenHeight: CGFloat { get }

    /// Encontra a tela que contém o ponto indicado (em coordenadas Cocoa).
    func screenContaining(point: CGPoint) -> NSScreen?

    /// Encontra a tela que contém o retângulo indicado.
    func screenContaining(rect: CGRect) -> NSScreen?
}

/// Contrato para o motor de aplicação de Snap em janelas.
@MainActor
public protocol WindowSnappingProtocol: AnyObject {
    /// Aplica uma zona de snap à janela focada.
    func snapFocusedWindow(to zone: SnapZone)

    /// Aplica uma zona de snap a uma janela específica.
    func snapWindow(_ window: WindowElement, to zone: SnapZone, on screen: NSScreen)
}

/// Contrato para monitoramento de eventos de entrada (mouse e teclado).
@MainActor
public protocol EventMonitoringProtocol: AnyObject {
    /// Inicia o monitoramento de eventos de arraste do mouse para detecção de snap.
    func startMonitoring()

    /// Interrompe o monitoramento de eventos.
    func stopMonitoring()
}
