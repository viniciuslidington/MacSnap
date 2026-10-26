import Cocoa
import ServiceManagement

/// Controla o ícone e menu do MacSnap na barra de menus superior do macOS (NSStatusItem).
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
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
        super.init()
        setupStatusItem()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        // Atualiza dinamicamente o status da permissão e do item de login cada vez que o menu abrir
        let isGranted = accessibilityService.isAccessibilityGranted(promptIfNeeded: false)
        menu.items.first?.title = isGranted ? "✓ Acessibilidade: Habilitada" : "⚠️ Acessibilidade: Requer Permissão"

        for item in menu.items {
            if item.action == #selector(toggleLaunchAtLogin) {
                let isLaunchAtLogin = isLoginItemEnabled()
                item.title = isLaunchAtLogin ? "✓ Iniciar com o Mac" : "Iniciar com o Mac"
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = makeMenuBarLogo()
            button.imagePosition = .imageOnly
        }

        rebuildMenu()
    }

    /// Gera o ícone vetorizado oficial do MacSnap no padrão visual do macOS (Retina-ready),
    /// representando duas janelas emparelhadas com barras de título e vão magnético central.
    private func makeMenuBarLogo() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let strokeColor = NSColor.black
            strokeColor.setStroke()

            // 1. Janela da Esquerda (com bordas arredondadas suaves)
            let leftRect = NSRect(x: 1.0, y: 1.5, width: 7.0, height: 13.0)
            let leftPath = NSBezierPath(roundedRect: leftRect, xRadius: 2.0, yRadius: 2.0)
            leftPath.lineWidth = 1.3
            leftPath.stroke()

            // Barra de título da janela esquerda
            let leftHeader = NSBezierPath()
            leftHeader.move(to: NSPoint(x: 1.8, y: 11.2))
            leftHeader.line(to: NSPoint(x: 7.2, y: 11.2))
            leftHeader.lineWidth = 1.0
            leftHeader.stroke()

            // 2. Janela da Direita
            let rightRect = NSRect(x: 10.0, y: 1.5, width: 7.0, height: 13.0)
            let rightPath = NSBezierPath(roundedRect: rightRect, xRadius: 2.0, yRadius: 2.0)
            rightPath.lineWidth = 1.3
            rightPath.stroke()

            // Barra de título da janela direita
            let rightHeader = NSBezierPath()
            rightHeader.move(to: NSPoint(x: 10.8, y: 11.2))
            rightHeader.line(to: NSPoint(x: 16.2, y: 11.2))
            rightHeader.lineWidth = 1.0
            rightHeader.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacSnap"
        return image
    }

    public func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

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

        // 3. Submenu de Colunas e Assimétricos Horizontais (16:9 / Ultrawide)
        let horizontalMenu = NSMenu()
        let leftThirdItem = NSMenuItem(title: "Coluna Esquerda (1/3)", action: #selector(snapLeftThird), keyEquivalent: "")
        leftThirdItem.target = self
        horizontalMenu.addItem(leftThirdItem)

        let centerThirdItem = NSMenuItem(title: "Coluna Central (1/3)", action: #selector(snapCenter), keyEquivalent: "")
        centerThirdItem.target = self
        horizontalMenu.addItem(centerThirdItem)

        let rightThirdItem = NSMenuItem(title: "Coluna Direita (1/3)", action: #selector(snapRightThird), keyEquivalent: "")
        rightThirdItem.target = self
        horizontalMenu.addItem(rightThirdItem)

        horizontalMenu.addItem(NSMenuItem.separator())

        let leftTwoThirdsItem = NSMenuItem(title: "Esquerda 2/3 + Direita 1/3", action: #selector(snapLeftTwoThirds), keyEquivalent: "")
        leftTwoThirdsItem.target = self
        horizontalMenu.addItem(leftTwoThirdsItem)

        let leftOneThirdItem = NSMenuItem(title: "Esquerda 1/3 + Direita 2/3 (Inverso)", action: #selector(snapLeftOneThird), keyEquivalent: "")
        leftOneThirdItem.target = self
        horizontalMenu.addItem(leftOneThirdItem)

        let horizontalParentItem = NSMenuItem(title: "Layouts Horizontais (16:9)", action: nil, keyEquivalent: "")
        horizontalParentItem.submenu = horizontalMenu
        menu.addItem(horizontalParentItem)

        // 4. Submenu de Layouts Verticais
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

        let topTwoThirdsItem = NSMenuItem(title: "Topo 2/3 + Base 1/3", action: #selector(snapTopTwoThirds), keyEquivalent: "")
        topTwoThirdsItem.target = self
        verticalMenu.addItem(topTwoThirdsItem)

        let bottomTwoThirdsItem = NSMenuItem(title: "Topo 1/3 + Base 2/3 (Inverso)", action: #selector(snapBottomTwoThirds), keyEquivalent: "")
        bottomTwoThirdsItem.target = self
        verticalMenu.addItem(bottomTwoThirdsItem)

        let verticalParentItem = NSMenuItem(title: "Layouts Verticais (Portrait)", action: nil, keyEquivalent: "")
        verticalParentItem.submenu = verticalMenu
        menu.addItem(verticalParentItem)

        menu.addItem(NSMenuItem.separator())

        let detectItem = NSMenuItem(title: "Reconectar Janelas Adjacentes", action: #selector(autoDetectWindows), keyEquivalent: "d")
        detectItem.target = self
        menu.addItem(detectItem)

        let clearPairItem = NSMenuItem(title: "Desfazer Divisor Emparelhado", action: #selector(clearPairing), keyEquivalent: "")
        clearPairItem.target = self
        menu.addItem(clearPairItem)

        menu.addItem(NSMenuItem.separator())

        // Iniciar com o Mac (Launch at Login via SMAppService)
        let isLaunchAtLogin = isLoginItemEnabled()
        let launchItem = NSMenuItem(
            title: isLaunchAtLogin ? "✓ Iniciar com o Mac" : "Iniciar com o Mac",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Sair
        let quitItem = NSMenuItem(title: "Encerrar MacSnap", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openAccessibilityPreferences() {
        _ = accessibilityService.isAccessibilityGranted(promptIfNeeded: true)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
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

    @objc private func snapBottomTwoThirds() {
        snapEngine.snapFocusedWindow(to: .bottomTwoThirds)
    }

    @objc private func snapLeftThird() {
        snapEngine.snapFocusedWindow(to: .leftThird)
    }

    @objc private func snapRightThird() {
        snapEngine.snapFocusedWindow(to: .rightThird)
    }

    @objc private func snapLeftTwoThirds() {
        snapEngine.snapFocusedWindow(to: .leftTwoThirds)
    }

    @objc private func snapLeftOneThird() {
        snapEngine.snapFocusedWindow(to: .leftOneThird)
    }

    @objc private func autoDetectWindows() {
        pairingManager.autoDetectAdjacentWindows()
    }

    @objc private func clearPairing() {
        pairingManager.clearPairing()
    }

    private func isLoginItemEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                print("[MacSnap] Desregistrado de itens de início.")
            } else {
                try SMAppService.mainApp.register()
                print("[MacSnap] Registrado para iniciar com o Mac com sucesso.")
            }
        } catch {
            print("[MacSnap] Erro ao alterar inicialização no login via SMAppService: \(error)")
        }
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
