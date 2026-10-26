import Cocoa

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared
    private let eventMonitor: EventMonitoringProtocol = GlobalEventMonitor.shared

    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("[MacSnap] Iniciando aplicação...")

        // Inicializa o menu da barra superior
        menuBarController = MenuBarController()

        // Verifica permissões de acessibilidade no início
        let hasPermission = accessibilityService.isAccessibilityGranted(promptIfNeeded: true)
        if !hasPermission {
            print("[MacSnap] Permissão de acessibilidade pendente. Solicitação apresentada ao usuário.")
        }

        // Ativa o monitoramento global de arraste de janelas e bordas
        eventMonitor.startMonitoring()

        // Auto-reconhecimento inicial de janelas adjacentes abertas em qualquer monitor
        PairedResizeManager.shared.autoDetectAdjacentWindows()

        // Observa ativação e alternância de janelas para auto-conectar janelas adjacentes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PairedResizeManager.shared.autoDetectAdjacentWindows()
            }
        }

        print("[MacSnap] Pronto para gerenciar janelas.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        eventMonitor.stopMonitoring()
        print("[MacSnap] Encerrando aplicação.")
    }
}
