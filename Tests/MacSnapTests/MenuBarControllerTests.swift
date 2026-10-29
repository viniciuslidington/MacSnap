import AppKit
import Testing
@testable import MacSnap

@MainActor
@Suite(.serialized)
struct MenuBarControllerTests {
    init() {
        _ = NSApplication.shared
    }

    @Test func quickSnapClickDoesNotKeepHoverWhenMenuReopens() throws {
        let engine = MenuTestSnapEngine()
        let controller = MenuBarController(
            accessibilityService: MenuTestAccessibility(),
            snapEngine: engine
        )
        let statusItem = try #require(controller.statusItem)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let menu = try #require(statusItem.menu)
        let left = try #require(button(named: "Left", in: menu))
        controller.menuWillOpen(menu)
        let neutral = background(of: left)

        // Closing a custom menu view on mouseDown need not deliver mouseExited.
        for _ in 0..<3 {
            left.mouseEntered(with: enteredEvent())
            #expect(background(of: left) != neutral)
            left.mouseDown(with: clickEvent())
            controller.menuWillOpen(menu)
            #expect(background(of: left) == neutral)
        }
        #expect(engine.zones == [.leftHalf, .leftHalf, .leftHalf])
    }

    @Test func dismissingMenuClearsHoverForQuickSnapAndActionButtons() throws {
        let controller = MenuBarController(accessibilityService: MenuTestAccessibility())
        let statusItem = try #require(controller.statusItem)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let menu = try #require(statusItem.menu)
        let delegate: any NSMenuDelegate = controller

        for title in ["Left", "Right", "Max", "Center", "Reconnect Pair", "Clear"] {
            let view = try #require(button(named: title, in: menu))
            controller.menuWillOpen(menu)
            let neutral = background(of: view)
            view.mouseEntered(with: enteredEvent())
            #expect(background(of: view) != neutral)
            delegate.menuDidClose?(menu)
            #expect(background(of: view) == neutral)
            controller.menuWillOpen(menu)
            #expect(background(of: view) == neutral)
        }
    }

    @Test func accessibilityPressClearsHoverAndPausedMenuRejectsActions() throws {
        let engine = MenuTestSnapEngine()
        let monitor = GlobalEventMonitor(
            accessibilityService: MenuTestAccessibility(),
            snapEngine: engine
        )
        let originalEnabled = monitor.isMasterEnabled
        let originalPreference = UserDefaults.standard.object(forKey: "MacSnap.isMasterEnabled")
        defer {
            monitor.isMasterEnabled = originalEnabled
            if let originalPreference {
                UserDefaults.standard.set(originalPreference, forKey: "MacSnap.isMasterEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "MacSnap.isMasterEnabled")
            }
        }
        monitor.isMasterEnabled = true
        let controller = MenuBarController(
            accessibilityService: MenuTestAccessibility(),
            snapEngine: engine,
            eventMonitor: monitor
        )
        let statusItem = try #require(controller.statusItem)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let menu = try #require(statusItem.menu)
        let left = try #require(button(named: "Left", in: menu))
        controller.menuWillOpen(menu)
        let neutral = background(of: left)

        left.mouseEntered(with: enteredEvent())
        #expect(background(of: left) != neutral)
        #expect(left.accessibilityPerformPress())
        #expect(background(of: left) == neutral)
        #expect(engine.zones == [.leftHalf])

        left.mouseEntered(with: enteredEvent())
        monitor.isMasterEnabled = false
        controller.menuWillOpen(menu)
        for title in ["Left", "Right", "Max", "Center", "Reconnect Pair", "Clear"] {
            let view = try #require(button(named: title, in: menu))
            #expect(!view.isAccessibilityEnabled())
            let disabledAppearance = background(of: view)
            view.mouseEntered(with: enteredEvent())
            #expect(background(of: view) == disabledAppearance)
            #expect(!view.accessibilityPerformPress())
            view.mouseDown(with: clickEvent())
            #expect(background(of: view) == disabledAppearance)
        }
        #expect(engine.zones == [.leftHalf])

        monitor.isMasterEnabled = true
        controller.menuWillOpen(menu)
        #expect(left.isAccessibilityEnabled())
        #expect(left.accessibilityPerformPress())
        #expect(engine.zones == [.leftHalf, .leftHalf])
    }

    private func button(named name: String, in menu: NSMenu) -> NSView? {
        func find(in view: NSView) -> NSView? {
            if view.accessibilityLabel() == name { return view }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        return menu.items.lazy.compactMap { $0.view }.compactMap { find(in: $0) }.first
    }

    private func background(of view: NSView) -> [Int] {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            NSColor.white.setFill()
            view.bounds.fill()
            view.draw(view.bounds)
        }
        // Sample the tile background, away from its icon, text and rounded edge.
        let color = bitmap.colorAt(x: 4, y: 24)!.usingColorSpace(.deviceRGB)!
        return [color.redComponent, color.greenComponent, color.blueComponent].map {
            Int(($0 * 255).rounded())
        }
    }

    private func enteredEvent() -> NSEvent {
        NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        )!
    }

    private func clickEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )!
    }
}

private struct MenuTestAccessibility: AccessibilityServiceProtocol {
    func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool { true }
    func getFocusedWindow() -> WindowElement? { nil }
    func getWindowUnderPoint(_ point: CGPoint) -> WindowElement? { nil }
}

@MainActor
private final class MenuTestSnapEngine: WindowSnappingProtocol {
    var zones: [SnapZone] = []
    func snapFocusedWindow(to zone: SnapZone) { zones.append(zone) }
    func snapWindow(_ window: WindowElement, to zone: SnapZone, on screen: NSScreen, forceExactSize: Bool) {}
}
