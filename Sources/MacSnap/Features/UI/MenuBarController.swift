import Cocoa

/// Controla o ícone e menu do MacSnap na barra de menus superior do macOS (NSStatusItem).
@MainActor
public final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let accessibilityService: AccessibilityServiceProtocol
    private let snapEngine: WindowSnappingProtocol
    private let pairingManager: PairedResizeManager

    public init(
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared,
        snapEngine: WindowSnappingProtocol = SnapEngine.shared,
        pairingManager: PairedResizeManager = PairedResizeManager.shared
    ) {
        self.accessibilityService = accessibilityService
        self.snapEngine = snapEngine
        self.pairingManager = pairingManager
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "MacSnap") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "◫"
            }
        }

        rebuildMenu()
    }

    public func rebuildMenu() {
        let menu = NSMenu()

        // 1. Indicador de permissões
        let isGranted = accessibilityService.isAccessibilityGranted(promptIfNeeded: false)
        let permTitle = isGranted ? "✓ Acessibilidade: Habilitada" : "⚠️ Acessibilidade: Requer Permissão"
        let permItem = NSMenuItem(title: permTitle, action: #selector(openAccessibilityPreferences), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Ações rápidas de Snap
        let leftItem = NSMenuItem(title: "Metade Esquerda", action: #selector(snapLeft), keyEquivalent: "")
        leftItem.target = self
        menu.addItem(leftItem)

        let rightItem = NSMenuItem(title: "Metade Direita", action: #selector(snapRight), keyEquivalent: "")
        rightItem.target = self
        menu.addItem(rightItem)

        let maxItem = NSMenuItem(title: "Maximizar Janela", action: #selector(snapMaximize), keyEquivalent: "")
        maxItem.target = self
        menu.addItem(maxItem)

        let centerItem = NSMenuItem(title: "Centralizar (Terço Médio)", action: #selector(snapCenter), keyEquivalent: "")
        centerItem.target = self
        menu.addItem(centerItem)

        menu.addItem(NSMenuItem.separator())

        let clearPairItem = NSMenuItem(title: "Desfazer Divisor Emparelhado", action: #selector(clearPairing), keyEquivalent: "")
        clearPairItem.target = self
        menu.addItem(clearPairItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Sair
        let quitItem = NSMenuItem(title: "Encerrar MacSnap", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openAccessibilityPreferences() {
        if !accessibilityService.isAccessibilityGranted(promptIfNeeded: true) {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func snapLeft() {
        snapEngine.snapFocusedWindow(to: .leftHalf)
    }

    @objc private func snapRight() {
        snapEngine.snapFocusedWindow(to: .rightHalf)
    }

    @objc private func snapMaximize() {
        snapEngine.snapFocusedWindow(to: .maximize)
    }

    @objc private func snapCenter() {
        snapEngine.snapFocusedWindow(to: .centerThird)
    }

    @objc private func clearPairing() {
        pairingManager.clearPairing()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
