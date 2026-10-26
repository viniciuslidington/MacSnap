import Testing
import CoreGraphics
import ApplicationServices
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
}
