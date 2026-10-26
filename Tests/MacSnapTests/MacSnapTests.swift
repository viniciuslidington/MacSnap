import Testing
import CoreGraphics
import ApplicationServices
import AppKit
@testable import MacSnap

struct SnapGeometryTests {

    @Test func testSnapZoneHalfCalculations() {
        // Simula uma tela de 1920x1080 com margem do dock/menu (ex: 1920x1050 visível)
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
        // Uma janela no topo da tela em Cocoa: Y = 880 (de 880 a 1080, altura 200)
        let cocoaTopWindow = CGRect(x: 100, y: 880, width: 400, height: 200)

        let axRect = ScreenGeometry.cocoaToAX(cocoaRect: cocoaTopWindow, primaryScreenHeight: primaryHeight)
        // No AX, o topo é Y = 0
        #expect(axRect.origin.x == 100)
        #expect(axRect.origin.y == 0)
        #expect(axRect.width == 400)
        #expect(axRect.height == 200)

        // Converte de volta para Cocoa e verifica paridade
        let restoredCocoa = ScreenGeometry.axToCocoa(axRect: axRect, primaryScreenHeight: primaryHeight)
        #expect(restoredCocoa == cocoaTopWindow)
    }

    @Test func testPairedSplitRatioCalculations() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 2000, height: 1000)

        // Criamos o objeto fictício para cálculo
        // Usamos ratio de 0.4 (40% para a esquerda, 60% para a direita)
        let dummyLeft = WindowElement(element: AXUIElementCreateSystemWide(), pid: 1)
        let dummyRight = WindowElement(element: AXUIElementCreateSystemWide(), pid: 2)
        let pair = PairedSplit(leftWindow: dummyLeft, rightWindow: dummyRight, visibleFrame: visibleFrame, ratio: 0.4)

        let (leftRect, rightRect) = pair.calculateFrames()

        #expect(leftRect.width == 800)
        #expect(rightRect.width == 1200)
        #expect(leftRect.origin.x == 0)
        #expect(rightRect.origin.x == 800)
        #expect(pair.dividerX == 800)

        // Testa o clamp de proporção mínima e máxima
        pair.ratio = 0.05
        #expect(pair.ratio == 0.15) // Não deixa diminuir além de 15%

        pair.ratio = 0.99
        #expect(pair.ratio == 0.85) // Não deixa passar de 85%
    }

    @Test func testVerticalPairedSplitWithMagneticSnapping() {
        // Simula tela vertical 1080x1920
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

        // Testa atração magnética em 50%
        // Se o cursor estiver em Y = 980 (que seria ratio ~0.49), deve travar magneticamente em 0.50
        verticalPair.updateRatioFromCursor(cursorCoordinate: 980, primaryScreenHeight: 1920)
        #expect(verticalPair.ratio == 0.50)

        // Testa atração magnética em 1/3 (quando ratio for ~0.333)
        // cursorCoordinate correspondente a ~34% do topo
        let cursorForOneThird = 1920.0 * (1.0 - 0.34)
        verticalPair.updateRatioFromCursor(cursorCoordinate: cursorForOneThird, primaryScreenHeight: 1920)
        #expect(abs(verticalPair.ratio - (1.0 / 3.0)) < 0.001)
    }

    @Test func testVerticalMonitorThirdsCalculations() {
        // Simula um monitor vertical (1080 x 1920, visível 1080 x 1890)
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
        // Simula monitor 16:9 padrão (1920x1080)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // 3 Colunas iguais
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

        // Assimétrico 2/3 + 1/3
        let left23 = SnapZone.leftTwoThirds.targetRect(for: visibleFrame)
        #expect(left23.origin.x == 0)
        #expect(left23.width == 1280)

        let right13 = SnapZone.rightOneThird.targetRect(for: visibleFrame)
        #expect(right13.origin.x == 1280)
        #expect(right13.width == 640)

        // Assimétrico Invertido: 1/3 + 2/3
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
        // Subview 0 é o backdrop de desfoque (NSVisualEffectView)
        // Subview 1 é o canvas de desenho dos cartões, garantindo que os itens nunca sejam encobertos
        #expect(barView?.subviews.first is NSVisualEffectView)
        #expect(barView?.subviews.last is SnapBarCanvasView)

        let previewWindow = PreviewOverlayWindow()
        let previewView = previewWindow.contentView
        #expect(previewView != nil)
        #expect(previewView?.subviews.count == 2)
        #expect(previewView?.subviews.first is NSVisualEffectView)
        #expect(previewView?.subviews.last is PreviewOverlayCanvasView)
    }

    @MainActor
    @Test func testDividerHoverOnlyVisibility() {
        let divider = DividerHandleWindow()
        let view = divider.contentView
        #expect(view != nil)
        // O divisor deve iniciar 100% invisível por padrão (alpha 0.0) para não poluir a tela
        #expect(view?.alphaValue == 0.0)

        // Simula a passagem do cursor (mouseEntered)
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

        // Simula o cursor saindo da área da costura (mouseExited)
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

        // Emparelha no Monitor 1
        manager.pair(first: dummy1, second: dummy2, orientation: .vertical, on: screen1, ratio: 0.5)
        #expect(manager.state(for: screen1).pair != nil)
        #expect(manager.activePairs.count == 1)

        // Emparelha no Monitor 2
        manager.pair(first: dummy3, second: dummy4, orientation: .horizontal, on: screen2, ratio: 0.5)

        // Verifica que o Monitor 1 NÃO foi esquecido! Ambos continuam emparelhados simultaneamente.
        #expect(manager.state(for: screen1).pair != nil)
        #expect(manager.state(for: screen2).pair != nil)
        #expect(manager.activePairs.count == 2)

        // Limpa
        manager.clearPairing()
        #expect(manager.activePairs.count == 0)
    }
}
