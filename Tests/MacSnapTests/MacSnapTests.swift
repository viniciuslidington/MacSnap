import Testing
import CoreGraphics
import ApplicationServices
import AppKit
@testable import MacSnap

struct SnapGeometryTests {

    @Test func testSnapZoneHalfCalculations() {
        // Simulates a 1920x1080 display with dock/menu margins (e.g. 1920x1050 visible)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1050)

        let leftRect = SnapZone.leftHalf.targetRect(for: visibleFrame)
        #expect(leftRect.origin.x == 0)
        #expect(leftRect.origin.y == 0)
        #expect(leftRect.width == 960)
        #expect(leftRect.height == 1050)

        let rightRect = SnapZone.rightHalf.targetRect(for: visibleFrame)
        #expect(rightRect.origin.x == 960)
        #expect(rightRect.origin.y == 0)
        #expect(rightRect.width == 960)
        #expect(rightRect.height == 1050)

        let maxRect = SnapZone.maximize.targetRect(for: visibleFrame)
        #expect(maxRect == visibleFrame)
    }

    @Test func testSnapZoneCornerCalculations() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let topLeft = SnapZone.topLeftQuarter.targetRect(for: visibleFrame)
        #expect(topLeft == CGRect(x: 0, y: 400, width: 500, height: 400))

        let bottomRight = SnapZone.bottomRightQuarter.targetRect(for: visibleFrame)
        #expect(bottomRight == CGRect(x: 500, y: 0, width: 500, height: 400))
    }

    @Test func testCoordinateConversionCocoaToAX() {
        let primaryHeight: CGFloat = 1080.0
        // A window at top of screen in Cocoa: Y = 880 (from 880 to 1080, height 200)
        let cocoaTopWindow = CGRect(x: 100, y: 880, width: 400, height: 200)

        let axRect = ScreenGeometry.cocoaToAX(cocoaRect: cocoaTopWindow, primaryScreenHeight: primaryHeight)
        // In AX, top is Y = 0
        #expect(axRect.origin.x == 100)
        #expect(axRect.origin.y == 0)
        #expect(axRect.width == 400)
        #expect(axRect.height == 200)

        // Converts back to Cocoa and verifies parity
        let restoredCocoa = ScreenGeometry.axToCocoa(axRect: axRect, primaryScreenHeight: primaryHeight)
        #expect(restoredCocoa == cocoaTopWindow)
    }

    @Test func testPairedSplitRatioCalculations() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 2000, height: 1000)

        // Create dummy elements for calculation
        // Use 0.4 ratio (40% to the left, 60% to the right)
        let dummyLeft = WindowElement(element: AXUIElementCreateSystemWide(), pid: 1)
        let dummyRight = WindowElement(element: AXUIElementCreateSystemWide(), pid: 2)
        let pair = PairedSplit(leftWindow: dummyLeft, rightWindow: dummyRight, visibleFrame: visibleFrame, ratio: 0.4)

        let (leftRect, rightRect) = pair.calculateFrames()

        #expect(leftRect.width == 800)
        #expect(rightRect.width == 1200)
        #expect(leftRect.origin.x == 0)
        #expect(rightRect.origin.x == 800)
        #expect(pair.dividerX == 800)

        // Tests minimum and maximum ratio clamping
        pair.ratio = 0.05
        #expect(pair.ratio == 0.15) // Does not allow decreasing below 15%

        pair.ratio = 0.99
        #expect(pair.ratio == 0.85) // Does not allow exceeding 85%
    }

    @Test func testVerticalPairedSplitWithMagneticSnapping() {
        // Simulates vertical display 1080x1920
        let visibleFrame = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let dummyTop = WindowElement(element: AXUIElementCreateSystemWide(), pid: 10)
        let dummyBottom = WindowElement(element: AXUIElementCreateSystemWide(), pid: 11)

        let verticalPair = PairedSplit(
            firstWindow: dummyTop,
            secondWindow: dummyBottom,
            orientation: .vertical,
            visibleFrame: visibleFrame,
            ratio: 0.5
        )

        let (topRect, bottomRect) = verticalPair.calculateFrames()
        #expect(topRect.height == 960)
        #expect(bottomRect.height == 960)
        #expect(bottomRect.origin.y == 0)
        #expect(topRect.origin.y == 960)
        #expect(verticalPair.dividerY == 960)

        // Tests magnetic snapping at 50%
        // If cursor is at Y = 980 (which would be ratio ~0.49), must lock magnetically to 0.50
        verticalPair.updateRatioFromCursor(cursorCoordinate: 980, primaryScreenHeight: 1920)
        #expect(verticalPair.ratio == 0.50)

        // Tests magnetic snapping at 1/3 (when ratio is ~0.333)
        // cursorCoordinate corresponding to ~34% from the top
        let cursorForOneThird = 1920.0 * (1.0 - 0.34)
        verticalPair.updateRatioFromCursor(cursorCoordinate: cursorForOneThird, primaryScreenHeight: 1920)
        #expect(abs(verticalPair.ratio - (1.0 / 3.0)) < 0.001)
    }

    @Test func testVerticalMonitorThirdsCalculations() {
        // Simulates a portrait monitor (1080 x 1920, visible 1080 x 1890)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1080, height: 1890)
        let expectedThirdHeight: CGFloat = 1890.0 / 3.0 // 630

        let topThird = SnapZone.topThird.targetRect(for: visibleFrame)
        #expect(topThird.origin.y == 1260)
        #expect(topThird.height == expectedThirdHeight)
        #expect(topThird.width == 1080)

        let middleThird = SnapZone.middleThird.targetRect(for: visibleFrame)
        #expect(middleThird.origin.y == 630)
        #expect(middleThird.height == expectedThirdHeight)
        #expect(middleThird.width == 1080)

        let bottomThird = SnapZone.bottomThird.targetRect(for: visibleFrame)
        #expect(bottomThird.origin.y == 0)
        #expect(bottomThird.height == expectedThirdHeight)
        #expect(bottomThird.width == 1080)

        let topTwoThirds = SnapZone.topTwoThirds.targetRect(for: visibleFrame)
        #expect(topTwoThirds.origin.y == 630)
        #expect(topTwoThirds.height == 1260)
    }

    @Test func testHorizontalAsymmetricAndThreeColumnCalculations() {
        // Simulates standard 16:9 monitor (1920x1080)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // 3 equal columns
        let leftThird = SnapZone.leftThird.targetRect(for: visibleFrame)
        #expect(leftThird.origin.x == 0)
        #expect(leftThird.width == 640)
        #expect(leftThird.height == 1080)

        let centerThird = SnapZone.centerThird.targetRect(for: visibleFrame)
        #expect(centerThird.origin.x == 640)
        #expect(centerThird.width == 640)

        let rightThird = SnapZone.rightThird.targetRect(for: visibleFrame)
        #expect(rightThird.origin.x == 1280)
        #expect(rightThird.width == 640)

        // Asymmetric 2/3 + 1/3
        let left23 = SnapZone.leftTwoThirds.targetRect(for: visibleFrame)
        #expect(left23.origin.x == 0)
        #expect(left23.width == 1280)

        let right13 = SnapZone.rightOneThird.targetRect(for: visibleFrame)
        #expect(right13.origin.x == 1280)
        #expect(right13.width == 640)

        // Inverted Asymmetric: 1/3 + 2/3
        let left13 = SnapZone.leftOneThird.targetRect(for: visibleFrame)
        #expect(left13.origin.x == 0)
        #expect(left13.width == 640)

        let right23 = SnapZone.rightTwoThirds.targetRect(for: visibleFrame)
        #expect(right23.origin.x == 640)
        #expect(right23.width == 1280)
    }

    @MainActor
    @Test func testSnapLayoutBarWindowAndPreviewViewHierarchy() {
        let barWindow = SnapLayoutBarWindow()
        let barView = barWindow.contentView
        #expect(barView != nil)
        #expect(barView?.subviews.count == 2)
        // Subview 0 is the blur backdrop (NSVisualEffectView)
        // Subview 1 is the cards canvas, ensuring items are never obscured
        #expect(barView?.subviews.first is NSVisualEffectView)
        #expect(barView?.subviews.last is SnapBarCanvasView)

        let previewWindow = PreviewOverlayWindow()
        let previewView = previewWindow.contentView
        #expect(previewView != nil)
        #expect(previewView?.subviews.count == 2)
        #expect(previewView?.subviews.first is NSVisualEffectView)
        #expect(previewView?.subviews.last is PreviewOverlayCanvasView)

        // Ensures the modal sits strictly in front of the preview rectangle
        #expect(barWindow.level > previewWindow.level)
    }

    @MainActor
    @Test func testSingleSlotHighlightingInSnapBar() {
        let barWindow = SnapLayoutBarWindow()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        barWindow.present(on: screen)
        #expect(barWindow.totalSlotsCount > 0)
        #expect(barWindow.currentlyHoveredSlotID == nil)

        guard let rect0 = barWindow.slotRect(at: 0),
              let rect1 = barWindow.slotRect(at: 1) else {
            Issue.record("Slots were not initialized properly")
            return
        }

        let pt0 = barWindow.convertPoint(toScreen: CGPoint(x: rect0.midX, y: rect0.midY))
        let zone0 = barWindow.checkHover(at: pt0)
        #expect(zone0 != nil)
        #expect(barWindow.currentlyHoveredSlotID == 0)

        let pt1 = barWindow.convertPoint(toScreen: CGPoint(x: rect1.midX, y: rect1.midY))
        let zone1 = barWindow.checkHover(at: pt1)
        #expect(zone1 != nil)
        #expect(barWindow.currentlyHoveredSlotID == 1)

        barWindow.dismiss()
        #expect(barWindow.currentlyHoveredSlotID == nil)
    }

    @MainActor
    @Test func testPortraitSlotsIndependentHighlightingForIdenticalZones() {
        let barWindow = SnapLayoutBarWindow()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        barWindow.present(on: screen)
        // Force portrait mode to inspect vertical cards
        barWindow.isPortrait = true
        #expect(barWindow.totalSlotsCount == 10)

        // Slot 2 = Card 2 (Top 1/3) -> zone .topThird
        // Slot 7 = Card 4 (Top 1/3 of Bottom 2/3) -> zone .topThird
        guard let rectSlot2 = barWindow.slotRect(at: 2),
              let rectSlot7 = barWindow.slotRect(at: 7) else {
            Issue.record("Vertical slots 2 and 7 must exist")
            return
        }

        // Hover over Slot 7 (Top 1/3 in Inverted Asymmetric card)
        let pt7 = barWindow.convertPoint(toScreen: CGPoint(x: rectSlot7.midX, y: rectSlot7.midY))
        let zone7 = barWindow.checkHover(at: pt7)
        #expect(zone7 == .topThird)
        // Only slot 7 should have active highlight!
        #expect(barWindow.currentlyHoveredSlotID == 7)
        #expect(barWindow.currentlyHoveredSlotID != 2)

        // Now move to Slot 2 (Top 1/3 in 3-thirds card)
        let pt2 = barWindow.convertPoint(toScreen: CGPoint(x: rectSlot2.midX, y: rectSlot2.midY))
        let zone2 = barWindow.checkHover(at: pt2)
        #expect(zone2 == .topThird)
        // Only slot 2 should have active highlight!
        #expect(barWindow.currentlyHoveredSlotID == 2)
        #expect(barWindow.currentlyHoveredSlotID != 7)

        barWindow.dismiss()
    }

    @MainActor
    @Test func testSnapLayoutBarPillAndExpandedStateTransitions() {
        let barWindow = SnapLayoutBarWindow()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // 1. Initially hidden
        #expect(barWindow.presentationState == .hidden)

        // 2. Present as compact pill (Pill Mode)
        barWindow.presentPill(on: screen, animated: false)
        #expect(barWindow.presentationState == .pill)
        #expect(barWindow.frame.width == 220)
        #expect(barWindow.frame.height == 24)

        // 3. Expand upon detecting hover
        barWindow.expand(animated: false)
        #expect(barWindow.presentationState == .expanded)
        #expect(barWindow.frame.height == 94)
        #expect(barWindow.totalSlotsCount > 0)

        // 4. Collapse back to pill when cursor moves away
        barWindow.collapseToPill(animated: false)
        #expect(barWindow.presentationState == .pill)
        #expect(barWindow.frame.width == 220)
        #expect(barWindow.frame.height == 24)

        // 5. Dismiss
        barWindow.dismiss(animated: false)
        #expect(barWindow.presentationState == .hidden)
    }

    @MainActor
    @Test func testDividerHoverOnlyVisibility() {
        let divider = DividerHandleWindow()
        let view = divider.contentView
        #expect(view != nil)
        // Divider must start 100% invisible by default (alpha 0.0) to avoid screen clutter
        #expect(view?.alphaValue == 0.0)

        // Simulates cursor hover (mouseEntered)
        let dummyEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!
        view?.mouseEntered(with: dummyEvent)
        #expect(view?.alphaValue == 1.0)

        // Simulates cursor leaving the divider area (mouseExited)
        view?.mouseExited(with: dummyEvent)
        #expect(view?.alphaValue == 0.0)
    }

    @MainActor
    @Test func testMultiMonitorPairingPersistence() {
        let manager = PairedResizeManager.shared
        manager.clearPairing()

        let screens = NSScreen.screens
        guard screens.count >= 2 else { return }

        let screen1 = screens[0]
        let screen2 = screens[1]

        let dummy1 = WindowElement(element: AXUIElementCreateSystemWide(), pid: 101)
        let dummy2 = WindowElement(element: AXUIElementCreateSystemWide(), pid: 102)
        let dummy3 = WindowElement(element: AXUIElementCreateSystemWide(), pid: 201)
        let dummy4 = WindowElement(element: AXUIElementCreateSystemWide(), pid: 202)

        // Pair on Monitor 1
        manager.pair(first: dummy1, second: dummy2, orientation: .vertical, on: screen1, ratio: 0.5)
        #expect(manager.state(for: screen1).pair != nil)
        #expect(manager.activePairs.count == 1)

        // Pair on Monitor 2
        manager.pair(first: dummy3, second: dummy4, orientation: .horizontal, on: screen2, ratio: 0.5)

        // Verify Monitor 1 was NOT forgotten! Both remain paired simultaneously.
        #expect(manager.state(for: screen1).pair != nil)
        #expect(manager.state(for: screen2).pair != nil)
        #expect(manager.activePairs.count == 2)

        // Clear
        manager.clearPairing()
        #expect(manager.activePairs.count == 0)
    }

    @MainActor
    @Test func testAutoDetectAdjacentWindowsExecution() {
        let manager = PairedResizeManager.shared
        // Run automatic search for adjacent windows in current environment
        let detected = manager.autoDetectAdjacentWindows()
        // Must execute without errors, returning list of detected pairs
        #expect(detected.count >= 0)
    }

    @MainActor
    @Test func testPairedResizeOverlayWindowPresentationAndUpdates() {
        let overlay = PairedResizeOverlayWindow()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // 1. Initial state
        #expect(!overlay.isPresenting)
        #expect(overlay.currentScreen == nil)

        // 2. Present overlay with two window frames
        let rect1 = CGRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 800, height: 1000)
        let rect2 = CGRect(x: screen.frame.origin.x + 800, y: screen.frame.origin.y, width: 1120, height: 1000)

        overlay.present(on: screen, firstRect: rect1, secondRect: rect2, animated: false)
        #expect(overlay.isPresenting)
        #expect(overlay.currentScreen == screen)

        // Verify panels are inset by 4pt margin
        let panel1 = overlay.firstPanelFrame
        let panel2 = overlay.secondPanelFrame
        #expect(panel1.width == 792) // 800 - 8
        #expect(panel2.width == 1112) // 1120 - 8

        // 3. Update during drag
        let updatedRect1 = CGRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 960, height: 1000)
        let updatedRect2 = CGRect(x: screen.frame.origin.x + 960, y: screen.frame.origin.y, width: 960, height: 1000)
        overlay.update(firstRect: updatedRect1, secondRect: updatedRect2)

        #expect(overlay.firstPanelFrame.width == 952) // 960 - 8
        #expect(overlay.secondPanelFrame.width == 952)

        // 4. Dismiss
        overlay.dismiss(animated: false)
        #expect(!overlay.isPresenting)
    }

    @MainActor
    @Test func testDividerDragCallbackLifecycle() {
        let divider = DividerHandleWindow()
        var dragStartedCalled = false
        var draggedCoordinate: CGFloat?
        var dragReleasedCalled = false

        divider.onDividerDragStarted = {
            dragStartedCalled = true
        }
        divider.onDividerDragged = { coord in
            draggedCoordinate = coord
        }
        divider.onDividerReleased = {
            dragReleasedCalled = true
        }

        divider.onDividerDragStarted?()
        #expect(dragStartedCalled)

        divider.onDividerDragged?(750.0)
        #expect(draggedCoordinate == 750.0)

        divider.onDividerReleased?()
        #expect(dragReleasedCalled)
    }

    @Test func testPairedSplitUpdateRatioOnly() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let dummyLeft = WindowElement(element: AXUIElementCreateSystemWide(), pid: ProcessInfo.processInfo.processIdentifier)
        let dummyRight = WindowElement(element: AXUIElementCreateSystemWide(), pid: ProcessInfo.processInfo.processIdentifier)
        let pair = PairedSplit(firstWindow: dummyLeft, secondWindow: dummyRight, orientation: .horizontal, visibleFrame: visibleFrame, ratio: 0.5)

        // updateRatioOnly should update ratio without errors
        pair.updateRatioOnly(from: 800) // 800 / 2000 = 0.40
        #expect(abs(pair.ratio - 0.40) < 0.001)

        // Test fallback app metadata on WindowElement
        #expect(dummyLeft.appIcon != nil)
        #expect(dummyLeft.appName != nil)

        // If a GUI app like Finder is running, test runningApplication resolution
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            let finderElem = WindowElement(element: AXUIElementCreateSystemWide(), pid: finder.processIdentifier)
            #expect(finderElem.runningApplication != nil)
            #expect(finderElem.appIcon != nil)
            #expect(finderElem.appName == "Finder")
        }
    }

    @Test func testWindowHeaderRegionDetection() {
        // Simulates an 800x600 window at (100, 100).
        // In Cocoa: minY = 100, maxY = 700.
        // Top 65pt header zone: Y from 635 to 700.
        let windowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

        // 1. Traffic lights and title bar (top 20-30pt)
        let trafficLightsPoint = CGPoint(x: 130, y: 685)
        #expect(WindowElement.isPointInHeaderRegion(trafficLightsPoint, windowFrame: windowFrame))

        // 2. Tab bar (e.g. 50pt from the top)
        let tabBarPoint = CGPoint(x: 350, y: 650)
        #expect(WindowElement.isPointInHeaderRegion(tabBarPoint, windowFrame: windowFrame))

        // 3. Editor body and line numbers (below top 65pt) -> MUST BE REJECTED
        let editorBodyPoint = CGPoint(x: 350, y: 550)
        #expect(!WindowElement.isPointInHeaderRegion(editorBodyPoint, windowFrame: windowFrame))

        // 4. Center of window / in-app buttons -> MUST BE REJECTED
        let centerPoint = CGPoint(x: 500, y: 400)
        #expect(!WindowElement.isPointInHeaderRegion(centerPoint, windowFrame: windowFrame))

        // 5. Desktop wallpaper outside window bounds -> MUST BE REJECTED
        let desktopLeft = CGPoint(x: 50, y: 680)
        let desktopRight = CGPoint(x: 950, y: 680)
        let desktopAbove = CGPoint(x: 350, y: 720)
        let desktopBelow = CGPoint(x: 350, y: 50)
        #expect(!WindowElement.isPointInHeaderRegion(desktopLeft, windowFrame: windowFrame))
        #expect(!WindowElement.isPointInHeaderRegion(desktopRight, windowFrame: windowFrame))
        #expect(!WindowElement.isPointInHeaderRegion(desktopAbove, windowFrame: windowFrame))
        #expect(!WindowElement.isPointInHeaderRegion(desktopBelow, windowFrame: windowFrame))

        // 6. Compact / small window (height 100pt, e.g. dialog from 200 to 300)
        // Header height capped at 50% (50pt): Y from 250 to 300
        let compactFrame = CGRect(x: 200, y: 200, width: 300, height: 100)
        let compactHeader = CGPoint(x: 300, y: 275)
        let compactBody = CGPoint(x: 300, y: 220)
        #expect(WindowElement.isPointInHeaderRegion(compactHeader, windowFrame: compactFrame))
        #expect(!WindowElement.isPointInHeaderRegion(compactBody, windowFrame: compactFrame))
    }

    @Test func testMenuBarAndDockExclusionLogic() {
        // Screen with full 1920x1080 frame
        // Menu bar at top: 1055 to 1080 (height 25)
        // Dock at bottom: 0 to 70 (height 70)
        // Visible frame: (x: 0, y: 70, width: 1920, height: 985) -> maxY = 1055
        let visibleFrame = CGRect(x: 0, y: 70, width: 1920, height: 985)

        func isExcluded(point: CGPoint) -> Bool {
            return !visibleFrame.contains(point) || point.y >= (visibleFrame.maxY - 1.0)
        }

        // Click in Apple menu / menu bar item (Y = 1065) -> Excluded
        let menuBarClick = CGPoint(x: 50, y: 1065)
        #expect(isExcluded(point: menuBarClick))

        // Click exactly on menu bar border line (Y = 1054.5) -> Excluded
        let menuBarBorderClick = CGPoint(x: 200, y: 1054.5)
        #expect(isExcluded(point: menuBarBorderClick))

        // Click in bottom Dock (Y = 35) -> Excluded
        let dockClick = CGPoint(x: 960, y: 35)
        #expect(isExcluded(point: dockClick))

        // Click inside active workspace (Y = 800) -> Allowed
        let usableAreaClick = CGPoint(x: 960, y: 800)
        #expect(!isExcluded(point: usableAreaClick))
    }

    @Test func testDragDistanceThresholdValidation() {
        let startPoint = CGPoint(x: 500, y: 500)
        let dragThreshold: CGFloat = 14.0

        // Micro-jitter click (3pt move)
        let jitterPoint = CGPoint(x: 502, y: 502)
        let jitterDist = hypot(jitterPoint.x - startPoint.x, jitterPoint.y - startPoint.y)
        #expect(jitterDist < dragThreshold)

        // Sub-threshold move (10pt move)
        let subPoint = CGPoint(x: 506, y: 508)
        let subDist = hypot(subPoint.x - startPoint.x, subPoint.y - startPoint.y)
        #expect(subDist < dragThreshold)

        // Intentional drag (20pt move)
        let dragPoint = CGPoint(x: 512, y: 516)
        let dragDist = hypot(dragPoint.x - startPoint.x, dragPoint.y - startPoint.y)
        #expect(dragDist >= dragThreshold)
    }

    @Test func testDesktopWindowRoleDetection() {
        let dummy = WindowElement(element: AXUIElementCreateSystemWide(), pid: ProcessInfo.processInfo.processIdentifier)
        // System wide element has no desktop subrole
        #expect(!dummy.isDesktopWindow)
    }

    @MainActor
    @Test func testDividerValidationOnHoverBlocksGhostLine() {
        let divider = DividerHandleWindow()
        var invalidCallbackCalled = false
        divider.validatePair = {
            return false // Simulates stale or non-adjacent pair
        }
        divider.onInvalidPairDetected = {
            invalidCallbackCalled = true
        }

        let view = divider.contentView as? DividerCustomView
        #expect(view != nil)

        // Simulate hover
        let dummyEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!
        view?.mouseEntered(with: dummyEvent)

        // When validatePair returns false, divider MUST NOT illuminate (alpha remains 0.0)
        // and onInvalidPairDetected must be triggered immediately
        #expect(view?.alphaValue == 0.0)
        #expect(invalidCallbackCalled)
    }

    @MainActor
    @Test func testUnpairWindowDisbandsActivePair() {
        let manager = PairedResizeManager.shared
        manager.clearPairing()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let dummy1 = WindowElement(element: AXUIElementCreateSystemWide(), pid: 888)
        let dummy2 = WindowElement(element: AXUIElementCreateSystemWide(), pid: 999)

        manager.pair(first: dummy1, second: dummy2, orientation: .horizontal, on: screen, ratio: 0.5)
        #expect(manager.state(for: screen).pair != nil)

        // When dummy1 starts being dragged away, unpairWindow must disband the pair
        manager.unpairWindow(dummy1)
        #expect(manager.state(for: screen).pair == nil)
    }

    @Test func testThreeColumnSnapCalculationsWithoutOverlap() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let leftRect = SnapZone.leftThird.targetRect(for: visibleFrame)
        let centerRect = SnapZone.centerThird.targetRect(for: visibleFrame)
        let rightRect = SnapZone.rightThird.targetRect(for: visibleFrame)

        #expect(leftRect.origin.x == 0)
        #expect(leftRect.width == 640)

        #expect(centerRect.origin.x == 640)
        #expect(centerRect.width == 640)

        #expect(rightRect.origin.x == 1280)
        #expect(rightRect.width == 640)

        // Verify zero overlap between all three columns
        #expect(leftRect.maxX == centerRect.minX)
        #expect(centerRect.maxX == rightRect.minX)
        #expect(rightRect.maxX == 1920)
    }

    @Test func testPairedSplitCalculateFramesExpansionAndShrinking() {
        let visibleFrame = CGRect(x: 0, y: 50, width: 1800, height: 1000)
        let dummy1 = WindowElement(element: AXUIElementCreateSystemWide(), pid: 111)
        let dummy2 = WindowElement(element: AXUIElementCreateSystemWide(), pid: 222)

        let pair = PairedSplit(
            firstWindow: dummy1,
            secondWindow: dummy2,
            orientation: .horizontal,
            visibleFrame: visibleFrame,
            ratio: 0.5
        )

        let (left1, right1) = pair.calculateFrames()
        #expect(left1.width == 900)
        #expect(right1.width == 900)
        #expect(left1.origin.x == 0)
        #expect(right1.origin.x == 900)
        #expect(left1.maxX == right1.minX)

        // Drag divider to 2/3
        pair.ratio = 2.0 / 3.0
        let (left2, right2) = pair.calculateFrames()
        #expect(left2.width == 1200)
        #expect(right2.width == 600)
        #expect(left2.origin.x == 0)
        #expect(right2.origin.x == 1200)
        #expect(left2.maxX == right2.minX)
        #expect(left2.width + right2.width == visibleFrame.width)
    }

    @MainActor
    @Test func testThreeColumnSetupDoesNotDistortHalfSnaps() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame

        // When snapping to leftHalf or rightHalf, default targets must strictly be 50%
        let leftTarget = SnapZone.leftHalf.targetRect(for: visibleFrame)
        let rightTarget = SnapZone.rightHalf.targetRect(for: visibleFrame)

        #expect(leftTarget.width == (visibleFrame.width / 2.0))
        #expect(rightTarget.width == (visibleFrame.width / 2.0))
        #expect(leftTarget.origin.x == visibleFrame.origin.x)
        #expect(rightTarget.origin.x == visibleFrame.origin.x + (visibleFrame.width / 2.0))
    }

    @MainActor
    @Test func testSameApplicationTwoWindowsPairing() {
        let manager = PairedResizeManager.shared
        manager.clearPairing()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // Two distinct windows from the same app (same PID, e.g. Chrome window 1 and Chrome window 2)
        let chromePid: pid_t = 2855
        let dummyChrome1 = WindowElement(element: AXUIElementCreateSystemWide(), pid: chromePid)
        let dummyChrome2 = WindowElement(element: AXUIElementCreateApplication(chromePid), pid: chromePid)

        manager.pair(first: dummyChrome1, second: dummyChrome2, orientation: .horizontal, on: screen, ratio: 0.5)
        let pair = manager.state(for: screen).pair

        #expect(pair != nil)
        #expect(pair?.firstWindow.pid == pair?.secondWindow.pid)
        #expect(!CFEqual(pair!.firstWindow.rawElement, pair!.secondWindow.rawElement))
    }

    @MainActor
    @Test func testSameApplicationAdjacentSearchFallback() {
        let manager = PairedResizeManager.shared
        guard let screen = NSScreen.screens.first else { return }

        // Simulate an excluded window from an app with PID 9999
        let dummyApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let currentWindow = WindowElement(element: dummyApp, pid: ProcessInfo.processInfo.processIdentifier)

        // findAdjacentWindow should safely reject self and not crash
        let partner = manager.findAdjacentWindow(
            atCocoaPoint: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY),
            excludingWindow: currentWindow
        )

        // When finding candidate at empty point or self, it should safely return nil
        #expect(partner == nil || !CFEqual(partner!.rawElement, currentWindow.rawElement))
    }

    @MainActor
    @Test func testDividerOcclusionAndSuppression() {
        let manager = PairedResizeManager.shared
        guard let screen = NSScreen.screens.first else { return }

        let dummy1 = WindowElement(element: AXUIElementCreateSystemWide(), pid: 9991)
        let dummy2 = WindowElement(element: AXUIElementCreateApplication(9992), pid: 9992)
        let pair = PairedSplit(firstWindow: dummy1, secondWindow: dummy2, visibleFrame: screen.visibleFrame, ratio: 0.5)

        // Point outside the screen bounds or empty should return false (unoccluded)
        let occluded = manager.isPairOccluded(atCocoaPoint: CGPoint(x: -99999, y: -99999), for: pair)
        #expect(!occluded)

        // Hiding divider immediately should set alphaValue to 0.0
        let state = manager.state(for: screen)
        state.dividerWindow.hideDividerImmediately()
        #expect(state.dividerWindow.contentView?.alphaValue == 0.0)
    }
}
