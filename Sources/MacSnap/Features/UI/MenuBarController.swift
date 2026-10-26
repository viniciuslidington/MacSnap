import Cocoa
import ServiceManagement

/// Controls the MacSnap status icon and menu in the macOS top menu bar (NSStatusItem).
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
        // Dynamically refresh accessibility permission status and login item checkmark whenever menu opens
        let isGranted = accessibilityService.isAccessibilityGranted(promptIfNeeded: false)
        menu.items.first?.title = isGranted ? "✓ Accessibility: Granted" : "⚠️ Accessibility: Permission Required"

        for item in menu.items {
            if item.action == #selector(toggleLaunchAtLogin) {
                let isLaunchAtLogin = isLoginItemEnabled()
                item.title = isLaunchAtLogin ? "✓ Launch at Login" : "Launch at Login"
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

    /// Generates the official vector MacSnap logo in native macOS Retina proportions,
    /// representing two paired windows with title bars and a central magnetic gap.
    private func makeMenuBarLogo() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let strokeColor = NSColor.black
            strokeColor.setStroke()

            // 1. Left Window (with smooth rounded corners)
            let leftRect = NSRect(x: 1.0, y: 1.5, width: 7.0, height: 13.0)
            let leftPath = NSBezierPath(roundedRect: leftRect, xRadius: 2.0, yRadius: 2.0)
            leftPath.lineWidth = 1.3
            leftPath.stroke()

            // Left window title bar
            let leftHeader = NSBezierPath()
            leftHeader.move(to: NSPoint(x: 1.8, y: 11.2))
            leftHeader.line(to: NSPoint(x: 7.2, y: 11.2))
            leftHeader.lineWidth = 1.0
            leftHeader.stroke()

            // 2. Right Window
            let rightRect = NSRect(x: 10.0, y: 1.5, width: 7.0, height: 13.0)
            let rightPath = NSBezierPath(roundedRect: rightRect, xRadius: 2.0, yRadius: 2.0)
            rightPath.lineWidth = 1.3
            rightPath.stroke()

            // Right window title bar
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

        // 1. Permissions indicator
        let isGranted = accessibilityService.isAccessibilityGranted(promptIfNeeded: false)
        let permTitle = isGranted ? "✓ Accessibility: Granted" : "⚠️ Accessibility: Permission Required"
        let permItem = NSMenuItem(title: permTitle, action: #selector(openAccessibilityPreferences), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Quick Snap actions
        let leftItem = NSMenuItem(title: "Left Half", action: #selector(snapLeft), keyEquivalent: "")
        leftItem.target = self
        menu.addItem(leftItem)

        let rightItem = NSMenuItem(title: "Right Half", action: #selector(snapRight), keyEquivalent: "")
        rightItem.target = self
        menu.addItem(rightItem)

        let maxItem = NSMenuItem(title: "Maximize Window", action: #selector(snapMaximize), keyEquivalent: "")
        maxItem.target = self
        menu.addItem(maxItem)

        let centerItem = NSMenuItem(title: "Center (Middle Third)", action: #selector(snapCenter), keyEquivalent: "")
        centerItem.target = self
        menu.addItem(centerItem)

        // 3. Submenu for Horizontal Columns and Asymmetric splits (16:9 / Ultrawide)
        let horizontalMenu = NSMenu()
        let leftThirdItem = NSMenuItem(title: "Left Column (1/3)", action: #selector(snapLeftThird), keyEquivalent: "")
        leftThirdItem.target = self
        horizontalMenu.addItem(leftThirdItem)

        let centerThirdItem = NSMenuItem(title: "Center Column (1/3)", action: #selector(snapCenter), keyEquivalent: "")
        centerThirdItem.target = self
        horizontalMenu.addItem(centerThirdItem)

        let rightThirdItem = NSMenuItem(title: "Right Column (1/3)", action: #selector(snapRightThird), keyEquivalent: "")
        rightThirdItem.target = self
        horizontalMenu.addItem(rightThirdItem)

        horizontalMenu.addItem(NSMenuItem.separator())

        let leftTwoThirdsItem = NSMenuItem(title: "Left 2/3 + Right 1/3", action: #selector(snapLeftTwoThirds), keyEquivalent: "")
        leftTwoThirdsItem.target = self
        horizontalMenu.addItem(leftTwoThirdsItem)

        let leftOneThirdItem = NSMenuItem(title: "Left 1/3 + Right 2/3 (Inverse)", action: #selector(snapLeftOneThird), keyEquivalent: "")
        leftOneThirdItem.target = self
        horizontalMenu.addItem(leftOneThirdItem)

        let horizontalParentItem = NSMenuItem(title: "Horizontal Layouts (16:9)", action: nil, keyEquivalent: "")
        horizontalParentItem.submenu = horizontalMenu
        menu.addItem(horizontalParentItem)

        // 4. Submenu for Vertical Layouts (Portrait)
        let verticalMenu = NSMenu()
        let topHalfItem = NSMenuItem(title: "Top Half", action: #selector(snapTopHalf), keyEquivalent: "")
        topHalfItem.target = self
        verticalMenu.addItem(topHalfItem)

        let bottomHalfItem = NSMenuItem(title: "Bottom Half", action: #selector(snapBottomHalf), keyEquivalent: "")
        bottomHalfItem.target = self
        verticalMenu.addItem(bottomHalfItem)

        verticalMenu.addItem(NSMenuItem.separator())

        let topThirdItem = NSMenuItem(title: "Top Third (1/3)", action: #selector(snapTopThird), keyEquivalent: "")
        topThirdItem.target = self
        verticalMenu.addItem(topThirdItem)

        let middleThirdItem = NSMenuItem(title: "Middle Third (1/3)", action: #selector(snapMiddleThird), keyEquivalent: "")
        middleThirdItem.target = self
        verticalMenu.addItem(middleThirdItem)

        let bottomThirdItem = NSMenuItem(title: "Bottom Third (1/3)", action: #selector(snapBottomThird), keyEquivalent: "")
        bottomThirdItem.target = self
        verticalMenu.addItem(bottomThirdItem)

        verticalMenu.addItem(NSMenuItem.separator())

        let topTwoThirdsItem = NSMenuItem(title: "Top 2/3 + Bottom 1/3", action: #selector(snapTopTwoThirds), keyEquivalent: "")
        topTwoThirdsItem.target = self
        verticalMenu.addItem(topTwoThirdsItem)

        let bottomTwoThirdsItem = NSMenuItem(title: "Top 1/3 + Bottom 2/3 (Inverse)", action: #selector(snapBottomTwoThirds), keyEquivalent: "")
        bottomTwoThirdsItem.target = self
        verticalMenu.addItem(bottomTwoThirdsItem)

        let verticalParentItem = NSMenuItem(title: "Vertical Layouts (Portrait)", action: nil, keyEquivalent: "")
        verticalParentItem.submenu = verticalMenu
        menu.addItem(verticalParentItem)

        menu.addItem(NSMenuItem.separator())

        let detectItem = NSMenuItem(title: "Reconnect Adjacent Windows", action: #selector(autoDetectWindows), keyEquivalent: "d")
        detectItem.target = self
        menu.addItem(detectItem)

        let clearPairItem = NSMenuItem(title: "Clear Paired Divider", action: #selector(clearPairing), keyEquivalent: "")
        clearPairItem.target = self
        menu.addItem(clearPairItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login via SMAppService
        let isLaunchAtLogin = isLoginItemEnabled()
        let launchItem = NSMenuItem(
            title: isLaunchAtLogin ? "✓ Launch at Login" : "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        // Quit MacSnap
        let quitItem = NSMenuItem(title: "Quit MacSnap", action: #selector(quitApp), keyEquivalent: "q")
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
                print("[MacSnap] Unregistered from login items.")
            } else {
                try SMAppService.mainApp.register()
                print("[MacSnap] Successfully registered to launch at login.")
            }
        } catch {
            print("[MacSnap] Error toggling launch at login via SMAppService: \(error)")
        }
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
