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

        // 3. Submenu de Layouts Verticais
        let verticalMenu = NSMenu()
        let topHalfItem = NSMenuItem(title: "Metade Superior", action: #selector(snapTopHalf), keyEquivalent: "")
        topHalfItem.target = self
        verticalMenu.addItem(topHalfItem)

        let bottomHalfItem = NSMenuItem(title: "Metade Inferior", action: #selector(snapBottomHalf), keyEquivalent: "")
        bottomHalfItem.target = self
        verticalMenu.addItem(bottomHalfItem)

        verticalMenu.addItem(NSMenuItem.separator())

        let topThirdItem = NSMenuItem(title: "Terço Superior (1/3)", action: #selector(snapTopThird), keyEquivalent: "")
        topThirdItem.target = self
        verticalMenu.addItem(topThirdItem)

        let middleThirdItem = NSMenuItem(title: "Terço Médio (1/3)", action: #selector(snapMiddleThird), keyEquivalent: "")
        middleThirdItem.target = self
        verticalMenu.addItem(middleThirdItem)

        let bottomThirdItem = NSMenuItem(title: "Terço Inferior (1/3)", action: #selector(snapBottomThird), keyEquivalent: "")
        bottomThirdItem.target = self
        verticalMenu.addItem(bottomThirdItem)

        verticalMenu.addItem(NSMenuItem.separator())

        let topTwoThirdsItem = NSMenuItem(title: "Dois Terços Superior (2/3)", action: #selector(snapTopTwoThirds), keyEquivalent: "")
        topTwoThirdsItem.target = self
        verticalMenu.addItem(topTwoThirdsItem)

        let verticalParentItem = NSMenuItem(title: "Layouts Verticais (Portrait)", action: nil, keyEquivalent: "")
        verticalParentItem.submenu = verticalMenu
        menu.addItem(verticalParentItem)

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

    @objc private func snapTopHalf() {
        snapEngine.snapFocusedWindow(to: .topHalf)
    }

    @objc private func snapBottomHalf() {
        snapEngine.snapFocusedWindow(to: .bottomHalf)
    }

    @objc private func snapTopThird() {
        snapEngine.snapFocusedWindow(to: .topThird)
    }

    @objc private func snapMiddleThird() {
        snapEngine.snapFocusedWindow(to: .middleThird)
    }

    @objc private func snapBottomThird() {
        snapEngine.snapFocusedWindow(to: .bottomThird)
    }

    @objc private func snapTopTwoThirds() {
        snapEngine.snapFocusedWindow(to: .topTwoThirds)
    }

    @objc private func clearPairing() {
        pairingManager.clearPairing()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
