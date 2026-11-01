import Cocoa
import ServiceManagement

/// Controls the MacSnap status icon and Control Center-style menu in the macOS top menu bar (`NSStatusItem`).
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private(set) var statusItem: NSStatusItem?
    private let accessibilityService: AccessibilityServiceProtocol
    private let snapEngine: WindowSnappingProtocol
    private let pairingManager: PairedResizeManager
    private let eventMonitor: GlobalEventMonitor
    private let appUpdater: any AppUpdating
    private let onUninstall: (() -> Void)?
    private var checkForUpdatesItem: NSMenuItem?
    private var automaticChecksItem: NSMenuItem?
    private var automaticInstallItem: NSMenuItem?

    private static let menuWidth: CGFloat = 310.0

    private weak var headerView: MenuHeaderView?
    private weak var quickSnapView: QuickSnapSectionView?
    private weak var controllersView: ControllersSectionView?
    private weak var footerView: MenuFooterSectionView?
    private weak var horizontalMenuItem: NSMenuItem?
    private weak var verticalMenuItem: NSMenuItem?

    init(
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared,
        snapEngine: WindowSnappingProtocol = SnapEngine.shared,
        pairingManager: PairedResizeManager = PairedResizeManager.shared,
        eventMonitor: GlobalEventMonitor = GlobalEventMonitor.shared,
        appUpdater: (any AppUpdating)? = nil,
        onUninstall: (() -> Void)? = nil
    ) {
        self.accessibilityService = accessibilityService
        self.snapEngine = snapEngine
        self.pairingManager = pairingManager
        self.eventMonitor = eventMonitor
        self.appUpdater = appUpdater ?? UnavailableAppUpdater()
        self.onUninstall = onUninstall
        super.init()
        setupStatusItem()
        self.appUpdater.onChange = { [weak self] in self?.refreshUpdateState() }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        resetMenuHoverState()
        refreshMenuState()
    }

    public func menuDidClose(_ menu: NSMenu) {
        resetMenuHoverState()
    }

    private func resetMenuHoverState() {
        quickSnapView?.resetHoverState()
        controllersView?.resetHoverState()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = makeMenuBarLogo()
            button.imagePosition = .imageOnly
            button.alphaValue = eventMonitor.isMasterEnabled ? 1.0 : 0.45
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
        menu.minimumWidth = Self.menuWidth
        menu.autoenablesItems = false

        // 1. Control Center Header (App Badge, Title, Active/Paused Pill, Accessibility Status & Master NSSwitch)
        let headerItem = NSMenuItem()
        let header = MenuHeaderView(
            width: Self.menuWidth,
            isMasterEnabled: eventMonitor.isMasterEnabled,
            isAccessibilityGranted: accessibilityService.isAccessibilityGranted(promptIfNeeded: false),
            onMasterToggle: { [weak self] isEnabled in
                self?.setMasterEnabled(isEnabled)
            },
            onOpenAccessibility: { [weak self] in
                self?.statusItem?.menu?.cancelTracking()
                self?.openAccessibilityPreferences()
            }
        )
        headerItem.view = header
        self.headerView = header
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Quick Snap Visual Grid (Left, Right, Max, Center - clean without shortcut labels)
        let quickSnapItem = NSMenuItem()
        let quickSnap = QuickSnapSectionView(
            width: Self.menuWidth,
            onSelectZone: { [weak self] zone in
                self?.statusItem?.menu?.cancelTracking()
                self?.snapEngine.snapFocusedWindow(to: zone)
            }
        )
        quickSnapItem.view = quickSnap
        self.quickSnapView = quickSnap
        menu.addItem(quickSnapItem)

        // 3. Submenu for Horizontal Layouts
        let horizontalMenu = buildHorizontalSubmenu()
        let horizontalParentItem = NSMenuItem(title: "Horizontal Layouts", action: nil, keyEquivalent: "")
        horizontalParentItem.image = makeLayoutIcon(isHorizontal: true)
        horizontalParentItem.submenu = horizontalMenu
        self.horizontalMenuItem = horizontalParentItem
        menu.addItem(horizontalParentItem)

        // 4. Submenu for Vertical Layouts
        let verticalMenu = buildVerticalSubmenu()
        let verticalParentItem = NSMenuItem(title: "Vertical Layouts", action: nil, keyEquivalent: "")
        verticalParentItem.image = makeLayoutIcon(isHorizontal: false)
        verticalParentItem.submenu = verticalMenu
        self.verticalMenuItem = verticalParentItem
        menu.addItem(verticalParentItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Controllers Card (Top Snap Bar, Edge & Corner Snap, Paired Window Divider + Reconnect Pair & Clear)
        let controllersItem = NSMenuItem()
        let controllers = ControllersSectionView(
            width: Self.menuWidth,
            isTopBarEnabled: eventMonitor.isTopSnapBarEnabled,
            isEdgeSnapEnabled: eventMonitor.isEdgeSnapEnabled,
            isDividerEnabled: pairingManager.isDividerEnabled,
            onToggleTopBar: { [weak self] isEnabled in
                self?.eventMonitor.isTopSnapBarEnabled = isEnabled
            },
            onToggleEdgeSnap: { [weak self] isEnabled in
                self?.eventMonitor.isEdgeSnapEnabled = isEnabled
            },
            onToggleDivider: { [weak self] isEnabled in
                self?.pairingManager.isDividerEnabled = isEnabled
            },
            onReconnectPair: { [weak self] in
                self?.statusItem?.menu?.cancelTracking()
                self?.pairingManager.autoDetectAdjacentWindows()
            },
            onClearPair: { [weak self] in
                self?.statusItem?.menu?.cancelTracking()
                self?.pairingManager.clearPairing()
            }
        )
        controllersItem.view = controllers
        self.controllersView = controllers
        menu.addItem(controllersItem)

        menu.addItem(NSMenuItem.separator())

        addUpdateMenu(to: menu)
        let uninstall = NSMenuItem(title: "Uninstall MacSnap…", action: #selector(uninstallMacSnap), keyEquivalent: "")
        uninstall.target = self
        uninstall.isEnabled = onUninstall != nil
        menu.addItem(uninstall)
        menu.addItem(NSMenuItem.separator())

        // 6. System & Footer (Launch at Login NSSwitch + Version + Quit)
        let footerItem = NSMenuItem()
        let versionText = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .map { "MacSnap v\($0)" } ?? "MacSnap Development"
        let footer = MenuFooterSectionView(
            width: Self.menuWidth,
            isLaunchAtLogin: isLoginItemEnabled(),
            versionText: versionText,
            onToggleLaunchAtLogin: { [weak self] _ in
                self?.toggleLaunchAtLogin()
            },
            onQuit: { [weak self] in
                self?.statusItem?.menu?.cancelTracking()
                self?.quitApp()
            }
        )
        footerItem.view = footer
        self.footerView = footer
        menu.addItem(footerItem)

        statusItem?.menu = menu
        refreshMenuState()
    }

    private func refreshMenuState() {
        refreshUpdateState()
        let isGranted = accessibilityService.isAccessibilityGranted(promptIfNeeded: false)
        let isMaster = eventMonitor.isMasterEnabled

        headerView?.updateState(isMasterEnabled: isMaster, isAccessibilityGranted: isGranted)
        quickSnapView?.setEnabledState(isMaster)
        controllersView?.updateState(
            isMasterEnabled: isMaster,
            isTopBarEnabled: eventMonitor.isTopSnapBarEnabled,
            isEdgeSnapEnabled: eventMonitor.isEdgeSnapEnabled,
            isDividerEnabled: pairingManager.isDividerEnabled
        )
        horizontalMenuItem?.isEnabled = isMaster
        verticalMenuItem?.isEnabled = isMaster
        footerView?.updateLaunchAtLogin(isLoginItemEnabled())
        statusItem?.button?.alphaValue = isMaster ? 1.0 : 0.45
    }

    private func addUpdateMenu(to menu: NSMenu) {
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        checkForUpdatesItem = check
        let preferences = NSMenu(title: "Updates")
        preferences.autoenablesItems = false
        let checks = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutomaticChecks), keyEquivalent: "")
        checks.target = self
        preferences.addItem(checks)
        automaticChecksItem = checks
        let install = NSMenuItem(title: "Automatically Download and Install", action: #selector(toggleAutomaticInstall), keyEquivalent: "")
        install.target = self
        preferences.addItem(install)
        automaticInstallItem = install
        let parent = NSMenuItem(title: "Updates", action: nil, keyEquivalent: "")
        parent.submenu = preferences
        menu.addItem(parent)
    }

    private func refreshUpdateState() {
        let state = appUpdater.presentation
        checkForUpdatesItem?.title = state.pendingVersion.map { "Update to \($0)…" } ?? "Check for Updates…"
        checkForUpdatesItem?.isEnabled = state.canCheck
        checkForUpdatesItem?.toolTip = state.isAvailable ? nil : "Updates are unavailable for this build."
        automaticChecksItem?.isEnabled = state.isAvailable
        automaticChecksItem?.state = appUpdater.automaticallyChecksForUpdates ? .on : .off
        automaticInstallItem?.isEnabled = state.isAvailable
        automaticInstallItem?.state = appUpdater.automaticallyInstallsUpdates ? .on : .off
    }

    @objc private func checkForUpdates() {
        guard appUpdater.presentation.canCheck else { return }
        statusItem?.menu?.cancelTracking()
        appUpdater.checkForUpdates()
    }

    @objc private func uninstallMacSnap() {
        guard let onUninstall else { return }
        statusItem?.menu?.cancelTracking()
        onUninstall()
    }

    @objc private func toggleAutomaticChecks() {
        guard appUpdater.presentation.isAvailable else { return }
        appUpdater.automaticallyChecksForUpdates.toggle()
    }

    @objc private func toggleAutomaticInstall() {
        guard appUpdater.presentation.isAvailable else { return }
        appUpdater.automaticallyInstallsUpdates.toggle()
    }

    private func setMasterEnabled(_ isEnabled: Bool) {
        eventMonitor.isMasterEnabled = isEnabled
        refreshMenuState()
    }

    private func buildHorizontalSubmenu() -> NSMenu {
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

        let leftOneThirdItem = NSMenuItem(title: "Left 1/3 + Right 2/3", action: #selector(snapLeftOneThird), keyEquivalent: "")
        leftOneThirdItem.target = self
        horizontalMenu.addItem(leftOneThirdItem)

        return horizontalMenu
    }

    private func buildVerticalSubmenu() -> NSMenu {
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

        let topTwoThirdsItem = NSMenuItem(title: "Top Two-Thirds (2/3)", action: #selector(snapTopTwoThirds), keyEquivalent: "")
        topTwoThirdsItem.target = self
        verticalMenu.addItem(topTwoThirdsItem)

        let bottomTwoThirdsItem = NSMenuItem(title: "Bottom Two-Thirds (2/3)", action: #selector(snapBottomTwoThirds), keyEquivalent: "")
        bottomTwoThirdsItem.target = self
        verticalMenu.addItem(bottomTwoThirdsItem)

        return verticalMenu
    }

    private func makeLayoutIcon(isHorizontal: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            if isHorizontal {
                let outer = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 13.0, height: 11.0), xRadius: 2.0, yRadius: 2.0)
                outer.lineWidth = 1.25
                outer.stroke()

                let line1 = NSBezierPath()
                line1.move(to: NSPoint(x: 5.8, y: 2.5))
                line1.line(to: NSPoint(x: 5.8, y: 13.5))
                line1.lineWidth = 1.1
                line1.stroke()

                let line2 = NSBezierPath()
                line2.move(to: NSPoint(x: 10.2, y: 2.5))
                line2.line(to: NSPoint(x: 10.2, y: 13.5))
                line2.lineWidth = 1.1
                line2.stroke()
            } else {
                let outer = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 1.5, width: 11.0, height: 13.0), xRadius: 2.0, yRadius: 2.0)
                outer.lineWidth = 1.25
                outer.stroke()

                let line1 = NSBezierPath()
                line1.move(to: NSPoint(x: 2.5, y: 5.8))
                line1.line(to: NSPoint(x: 13.5, y: 5.8))
                line1.lineWidth = 1.1
                line1.stroke()

                let line2 = NSBezierPath()
                line2.move(to: NSPoint(x: 2.5, y: 10.2))
                line2.line(to: NSPoint(x: 13.5, y: 10.2))
                line2.lineWidth = 1.1
                line2.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func openAccessibilityPreferences() {
        if !accessibilityService.isAccessibilityGranted(promptIfNeeded: false) {
            let alert = NSAlert()
            alert.messageText = "Allow MacSnap to manage windows"
            alert.informativeText = "After an update, macOS may keep authorization for an older version, even with MacSnap enabled in Accessibility settings. Remove the old MacSnap entry, then add this installed app again. You do not need to reinstall MacSnap.\n\nMacSnap will resume monitoring automatically once access is granted."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
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
        footerView?.updateLaunchAtLogin(isLoginItemEnabled())
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - 1. Header View (App Badge + Status Pill + Accessibility Dot + Master NSSwitch)

@MainActor
private final class MenuHeaderView: NSView {
    private let statusPillLabel = NSTextField(labelWithString: "Active")
    private let statusPillContainer = NSView()
    private let accessibilityDot = NSView()
    private let accessibilityButton = NSButton()
    private let masterSwitch = NSSwitch()
    private let onMasterToggle: (Bool) -> Void
    private let onOpenAccessibility: () -> Void

    init(
        width: CGFloat,
        isMasterEnabled: Bool,
        isAccessibilityGranted: Bool,
        onMasterToggle: @escaping (Bool) -> Void,
        onOpenAccessibility: @escaping () -> Void
    ) {
        self.onMasterToggle = onMasterToggle
        self.onOpenAccessibility = onOpenAccessibility
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 52))
        setupUI()
        updateState(isMasterEnabled: isMasterEnabled, isAccessibilityGranted: isAccessibilityGranted)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        let badgeView = AppBadgeIconView(frame: NSRect(x: 14, y: 10, width: 32, height: 32))
        addSubview(badgeView)

        let titleLabel = NSTextField(labelWithString: "MacSnap")
        titleLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 54, y: 25, width: 65, height: 18)
        addSubview(titleLabel)

        statusPillContainer.wantsLayer = true
        statusPillContainer.layer?.cornerRadius = 4.5
        statusPillContainer.frame = NSRect(x: 121, y: 26, width: 48, height: 16)

        statusPillLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        statusPillLabel.alignment = .center
        statusPillLabel.frame = NSRect(x: 0, y: 1, width: 48, height: 14)
        statusPillContainer.addSubview(statusPillLabel)
        addSubview(statusPillContainer)

        accessibilityDot.wantsLayer = true
        accessibilityDot.layer?.cornerRadius = 3.5
        accessibilityDot.frame = NSRect(x: 55, y: 11, width: 7, height: 7)
        addSubview(accessibilityDot)

        accessibilityButton.isBordered = false
        accessibilityButton.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        accessibilityButton.contentTintColor = .secondaryLabelColor
        accessibilityButton.alignment = .left
        accessibilityButton.target = self
        accessibilityButton.action = #selector(accessibilityClicked)
        accessibilityButton.frame = NSRect(x: 66, y: 6, width: 175, height: 16)
        addSubview(accessibilityButton)

        masterSwitch.controlSize = .small
        masterSwitch.target = self
        masterSwitch.action = #selector(masterSwitchChanged)
        masterSwitch.frame = NSRect(x: bounds.width - 52, y: 15, width: 38, height: 22)
        addSubview(masterSwitch)
    }

    func updateState(isMasterEnabled: Bool, isAccessibilityGranted: Bool) {
        masterSwitch.state = isMasterEnabled ? .on : .off

        if isMasterEnabled {
            statusPillLabel.stringValue = "Active"
            statusPillLabel.textColor = .labelColor
            statusPillContainer.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        } else {
            statusPillLabel.stringValue = "Paused"
            statusPillLabel.textColor = NSColor.secondaryLabelColor
            statusPillContainer.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        }

        if isAccessibilityGranted {
            accessibilityDot.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
            accessibilityButton.title = "Accessibility Granted"
            accessibilityButton.contentTintColor = .secondaryLabelColor
        } else {
            accessibilityDot.layer?.backgroundColor = NSColor.labelColor.cgColor
            accessibilityButton.title = "Permission Required"
            accessibilityButton.contentTintColor = .labelColor
        }
    }

    @objc private func masterSwitchChanged() {
        onMasterToggle(masterSwitch.state == .on)
    }

    @objc private func accessibilityClicked() {
        onOpenAccessibility()
    }
}

private final class AppBadgeIconView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8.0, yRadius: 8.0)
        let gradient = NSGradient(
            starting: NSColor.labelColor.withAlphaComponent(0.12),
            ending: NSColor.labelColor.withAlphaComponent(0.05)
        )
        gradient?.draw(in: path, angle: -45)

        NSColor.labelColor.setStroke()
        let leftWindow = NSBezierPath(roundedRect: NSRect(x: 7.0, y: 8.5, width: 7.5, height: 15.0), xRadius: 1.8, yRadius: 1.8)
        leftWindow.lineWidth = 1.4
        leftWindow.stroke()

        let rightWindow = NSBezierPath(roundedRect: NSRect(x: 17.5, y: 8.5, width: 7.5, height: 15.0), xRadius: 1.8, yRadius: 1.8)
        rightWindow.lineWidth = 1.4
        rightWindow.stroke()
    }
}

// MARK: - 2. Quick Snap Visual Bento Grid (Clean: Icon + Title Only)

@MainActor
private final class QuickSnapSectionView: NSView {
    private var tiles: [QuickSnapTileButton] = []

    init(width: CGFloat, onSelectZone: @escaping (SnapZone) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 80))

        let sectionLabel = NSTextField(labelWithString: "QUICK SNAP")
        sectionLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        sectionLabel.textColor = .secondaryLabelColor
        sectionLabel.frame = NSRect(x: 14, y: 58, width: 120, height: 14)
        addSubview(sectionLabel)

        let items: [(String, SnapZone)] = [
            ("Left", .leftHalf),
            ("Right", .rightHalf),
            ("Max", .maximize),
            ("Center", .centerThird)
        ]

        let sidePadding: CGFloat = 12.0
        let spacing: CGFloat = 6.0
        let totalSpacing = spacing * CGFloat(items.count - 1)
        let tileWidth = floor((width - (sidePadding * 2) - totalSpacing) / CGFloat(items.count))
        let tileHeight: CGFloat = 48.0

        for (index, item) in items.enumerated() {
            let x = sidePadding + CGFloat(index) * (tileWidth + spacing)
            let tile = QuickSnapTileButton(
                frame: NSRect(x: x, y: 6, width: tileWidth, height: tileHeight),
                title: item.0,
                zone: item.1,
                onClick: { onSelectZone(item.1) }
            )
            addSubview(tile)
            tiles.append(tile)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEnabledState(_ enabled: Bool) {
        alphaValue = enabled ? 1.0 : 0.4
        tiles.forEach { $0.isEnabled = enabled }
    }

    func resetHoverState() {
        tiles.forEach { $0.resetHoverState() }
    }
}

@MainActor
private final class QuickSnapTileButton: NSView {
    private let title: String
    private let zone: SnapZone
    private let onClick: () -> Void
    private var isHovered = false
    var isEnabled = true {
        didSet {
            setAccessibilityEnabled(isEnabled)
            if !isEnabled { resetHoverState() }
        }
    }

    init(frame: NSRect, title: String, zone: SnapZone, onClick: @escaping () -> Void) {
        self.title = title
        self.zone = zone
        self.onClick = onClick
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        resetHoverState()
    }

    func resetHoverState() {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        _ = accessibilityPerformPress()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        // Closing menu tracking need not send mouseExited to this view.
        resetHoverState()
        onClick()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.0, yRadius: 9.0)
        let highlighted = isHovered && isEnabled
        NSColor.labelColor.withAlphaComponent(highlighted ? 0.12 : 0.06).setFill()
        bgPath.fill()
        NSColor.labelColor.withAlphaComponent(highlighted ? 0.18 : 0.10).setStroke()
        bgPath.lineWidth = 1.0
        bgPath.stroke()

        let fgColor = NSColor.labelColor

        // Draw proportional screen & active zone icon at top center
        let iconWidth: CGFloat = 22.0
        let iconHeight: CGFloat = 15.0
        let iconRect = NSRect(
            x: (bounds.width - iconWidth) / 2.0,
            y: bounds.height - iconHeight - 7.0,
            width: iconWidth,
            height: iconHeight
        )
        let screenOutline = NSBezierPath(roundedRect: iconRect, xRadius: 2.5, yRadius: 2.5)
        fgColor.withAlphaComponent(0.45).setStroke()
        screenOutline.lineWidth = 1.25
        screenOutline.stroke()

        let innerRect: NSRect
        switch zone {
        case .leftHalf:
            innerRect = NSRect(x: iconRect.minX + 2.0, y: iconRect.minY + 2.0, width: 8.0, height: iconRect.height - 4.0)
        case .rightHalf:
            innerRect = NSRect(x: iconRect.maxX - 10.0, y: iconRect.minY + 2.0, width: 8.0, height: iconRect.height - 4.0)
        case .maximize:
            innerRect = iconRect.insetBy(dx: 2.0, dy: 2.0)
        default:
            innerRect = NSRect(x: iconRect.midX - 5.0, y: iconRect.minY + 2.5, width: 10.0, height: iconRect.height - 5.0)
        }
        let zonePath = NSBezierPath(roundedRect: innerRect, xRadius: 1.3, yRadius: 1.3)
        fgColor.setFill()
        zonePath.fill()

        // Draw clean label below icon (no shortcut symbols)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: fgColor,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(x: 2, y: 5, width: bounds.width - 4, height: 15)
        (title as NSString).draw(in: textRect, withAttributes: attrs)
    }
}

// MARK: - 3. Controllers Section View (3 NSSwitch Rows + Reconnect Pair & Clear Buttons)

@MainActor
private final class ControllersSectionView: NSView {
    private let topBarSwitch = NSSwitch()
    private let edgeSnapSwitch = NSSwitch()
    private let dividerSwitch = NSSwitch()
    private var reconnectButton: ActionPillButton?
    private var clearButton: ActionPillButton?

    private let onToggleTopBar: (Bool) -> Void
    private let onToggleEdgeSnap: (Bool) -> Void
    private let onToggleDivider: (Bool) -> Void

    init(
        width: CGFloat,
        isTopBarEnabled: Bool,
        isEdgeSnapEnabled: Bool,
        isDividerEnabled: Bool,
        onToggleTopBar: @escaping (Bool) -> Void,
        onToggleEdgeSnap: @escaping (Bool) -> Void,
        onToggleDivider: @escaping (Bool) -> Void,
        onReconnectPair: @escaping () -> Void,
        onClearPair: @escaping () -> Void
    ) {
        self.onToggleTopBar = onToggleTopBar
        self.onToggleEdgeSnap = onToggleEdgeSnap
        self.onToggleDivider = onToggleDivider
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 172))

        let sectionLabel = NSTextField(labelWithString: "CONTROLLERS")
        sectionLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        sectionLabel.textColor = .secondaryLabelColor
        sectionLabel.frame = NSRect(x: 14, y: 150, width: 120, height: 14)
        addSubview(sectionLabel)

        let cardRect = NSRect(x: 12, y: 40, width: width - 24, height: 104)
        let cardView = RoundedCardContainerView(frame: cardRect)
        addSubview(cardView)

        // Row 1: Top Snap Bar
        let row1 = makeControllerRow(
            width: cardRect.width,
            y: 68,
            title: "Top Snap Bar",
            iconKind: .topBar,
            toggle: topBarSwitch,
            action: #selector(topBarSwitchChanged)
        )
        cardView.addSubview(row1)

        // Row 2: Edge & Corner Snap
        let row2 = makeControllerRow(
            width: cardRect.width,
            y: 35,
            title: "Edge & Corner Snap",
            iconKind: .edgeSnap,
            toggle: edgeSnapSwitch,
            action: #selector(edgeSnapSwitchChanged)
        )
        cardView.addSubview(row2)

        // Row 3: Paired Window Divider
        let row3 = makeControllerRow(
            width: cardRect.width,
            y: 2,
            title: "Paired Window Divider",
            iconKind: .divider,
            toggle: dividerSwitch,
            action: #selector(dividerSwitchChanged)
        )
        cardView.addSubview(row3)

        // Bottom Action Buttons: Reconnect Pair & Clear
        let clearW: CGFloat = 68.0
        let spacing: CGFloat = 6.0
        let reconnectW = (width - 24.0) - clearW - spacing

        let reconnectBtn = ActionPillButton(
            frame: NSRect(x: 12, y: 6, width: reconnectW, height: 28),
            title: "Reconnect Pair",
            onClick: onReconnectPair
        )
        addSubview(reconnectBtn)
        self.reconnectButton = reconnectBtn

        let clearBtn = ActionPillButton(
            frame: NSRect(x: 12 + reconnectW + spacing, y: 6, width: clearW, height: 28),
            title: "Clear",
            onClick: onClearPair
        )
        addSubview(clearBtn)
        self.clearButton = clearBtn

        updateState(
            isMasterEnabled: true,
            isTopBarEnabled: isTopBarEnabled,
            isEdgeSnapEnabled: isEdgeSnapEnabled,
            isDividerEnabled: isDividerEnabled
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeControllerRow(
        width: CGFloat,
        y: CGFloat,
        title: String,
        iconKind: ControllerIconView.IconKind,
        toggle: NSSwitch,
        action: Selector
    ) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: y, width: width, height: 32))

        let iconView = ControllerIconView(
            frame: NSRect(x: 8, y: 4, width: 24, height: 24),
            kind: iconKind
        )
        row.addSubview(iconView)

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .labelColor
        label.frame = NSRect(x: 40, y: 7, width: width - 92, height: 18)
        row.addSubview(label)

        toggle.controlSize = .small
        toggle.target = self
        toggle.action = action
        toggle.frame = NSRect(x: width - 46, y: 5, width: 38, height: 22)
        row.addSubview(toggle)

        return row
    }

    func updateState(
        isMasterEnabled: Bool,
        isTopBarEnabled: Bool,
        isEdgeSnapEnabled: Bool,
        isDividerEnabled: Bool
    ) {
        alphaValue = isMasterEnabled ? 1.0 : 0.4
        topBarSwitch.isEnabled = isMasterEnabled
        edgeSnapSwitch.isEnabled = isMasterEnabled
        dividerSwitch.isEnabled = isMasterEnabled
        topBarSwitch.state = isTopBarEnabled ? .on : .off
        edgeSnapSwitch.state = isEdgeSnapEnabled ? .on : .off
        dividerSwitch.state = isDividerEnabled ? .on : .off
        reconnectButton?.isEnabled = isMasterEnabled && isDividerEnabled
        clearButton?.isEnabled = isMasterEnabled && isDividerEnabled
    }

    func resetHoverState() {
        reconnectButton?.resetHoverState()
        clearButton?.resetHoverState()
    }

    @objc private func topBarSwitchChanged() {
        onToggleTopBar(topBarSwitch.state == .on)
    }

    @objc private func edgeSnapSwitchChanged() {
        onToggleEdgeSnap(edgeSnapSwitch.state == .on)
    }

    @objc private func dividerSwitchChanged() {
        let isOn = dividerSwitch.state == .on
        onToggleDivider(isOn)
        reconnectButton?.isEnabled = isOn
        clearButton?.isEnabled = isOn
    }
}

private final class RoundedCardContainerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10.0, yRadius: 10.0)
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.09).setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }
}

private final class ControllerIconView: NSView {
    enum IconKind {
        case topBar
        case edgeSnap
        case divider
    }

    private let kind: IconKind
    init(frame: NSRect, kind: IconKind) {
        self.kind = kind
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 6.0, yRadius: 6.0)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        bg.fill()

        NSColor.secondaryLabelColor.setStroke()
        NSColor.secondaryLabelColor.setFill()

        switch kind {
        case .topBar:
            let outer = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 5.0, width: 15.0, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            outer.lineWidth = 1.35
            outer.stroke()
            let pill = NSBezierPath(roundedRect: NSRect(x: 7.5, y: 15.2, width: 9.0, height: 3.2), xRadius: 1.0, yRadius: 1.0)
            pill.fill()

        case .edgeSnap:
            let path = NSBezierPath()
            // Top-left corner bracket
            path.move(to: NSPoint(x: 5, y: 15))
            path.line(to: NSPoint(x: 5, y: 19))
            path.line(to: NSPoint(x: 9, y: 19))
            // Top-right corner bracket
            path.move(to: NSPoint(x: 15, y: 19))
            path.line(to: NSPoint(x: 19, y: 19))
            path.line(to: NSPoint(x: 19, y: 15))
            // Bottom-right corner bracket
            path.move(to: NSPoint(x: 19, y: 9))
            path.line(to: NSPoint(x: 19, y: 5))
            path.line(to: NSPoint(x: 15, y: 5))
            // Bottom-left corner bracket
            path.move(to: NSPoint(x: 9, y: 5))
            path.line(to: NSPoint(x: 5, y: 5))
            path.line(to: NSPoint(x: 5, y: 9))
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.stroke()

        case .divider:
            let centerLine = NSBezierPath()
            centerLine.move(to: NSPoint(x: 12, y: 4.5))
            centerLine.line(to: NSPoint(x: 12, y: 19.5))
            centerLine.lineWidth = 1.6
            centerLine.lineCapStyle = .round
            centerLine.stroke()

            let arrows = NSBezierPath()
            arrows.move(to: NSPoint(x: 8.5, y: 9.5))
            arrows.line(to: NSPoint(x: 6.0, y: 12.0))
            arrows.line(to: NSPoint(x: 8.5, y: 14.5))

            arrows.move(to: NSPoint(x: 15.5, y: 9.5))
            arrows.line(to: NSPoint(x: 18.0, y: 12.0))
            arrows.line(to: NSPoint(x: 15.5, y: 14.5))
            arrows.lineWidth = 1.35
            arrows.lineCapStyle = .round
            arrows.lineJoinStyle = .round
            arrows.stroke()
        }
    }
}

@MainActor
private final class ActionPillButton: NSView {
    private let title: String
    private let onClick: () -> Void
    private var isHovered = false
    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.45
            setAccessibilityEnabled(isEnabled)
            if !isEnabled { resetHoverState() }
            needsDisplay = true
        }
    }

    init(frame: NSRect, title: String, onClick: @escaping () -> Void) {
        self.title = title
        self.onClick = onClick
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        resetHoverState()
    }

    func resetHoverState() {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        _ = accessibilityPerformPress()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        resetHoverState()
        onClick()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7.5, yRadius: 7.5)
        let highlighted = isHovered && isEnabled
        NSColor.labelColor.withAlphaComponent(highlighted ? 0.13 : 0.07).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(highlighted ? 0.18 : 0.10).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let textColor = NSColor.labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.0, weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(x: 4, y: 6, width: bounds.width - 8, height: 16)
        (title as NSString).draw(in: textRect, withAttributes: attrs)
    }
}

// MARK: - 4. System & Footer View (Launch at Login Switch + Version + Quit)

@MainActor
private final class MenuFooterSectionView: NSView {
    private let loginSwitch = NSSwitch()
    private let onToggleLaunchAtLogin: (Bool) -> Void
    private let onQuit: () -> Void

    init(
        width: CGFloat,
        isLaunchAtLogin: Bool,
        versionText: String,
        onToggleLaunchAtLogin: @escaping (Bool) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        self.onQuit = onQuit
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 60))

        let loginLabel = NSTextField(labelWithString: "Launch at Login")
        loginLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        loginLabel.textColor = .labelColor
        loginLabel.frame = NSRect(x: 16, y: 34, width: 160, height: 18)
        addSubview(loginLabel)

        loginSwitch.controlSize = .small
        loginSwitch.state = isLaunchAtLogin ? .on : .off
        loginSwitch.target = self
        loginSwitch.action = #selector(loginSwitchChanged)
        loginSwitch.frame = NSRect(x: width - 52, y: 32, width: 38, height: 22)
        addSubview(loginSwitch)

        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.frame = NSRect(x: 16, y: 6, width: 140, height: 16)
        addSubview(versionLabel)

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitClicked))
        quitButton.isBordered = false
        quitButton.font = NSFont.systemFont(ofSize: 12.0, weight: .medium)
        quitButton.contentTintColor = .secondaryLabelColor
        quitButton.alignment = .right
        quitButton.frame = NSRect(x: width - 66, y: 5, width: 50, height: 18)
        addSubview(quitButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        loginSwitch.state = enabled ? .on : .off
    }

    @objc private func loginSwitchChanged() {
        onToggleLaunchAtLogin(loginSwitch.state == .on)
    }

    @objc private func quitClicked() {
        onQuit()
    }
}
