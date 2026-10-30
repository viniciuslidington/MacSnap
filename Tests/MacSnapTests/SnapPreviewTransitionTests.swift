import AppKit
import Testing
@testable import MacSnap

@MainActor
@Suite(.serialized)
struct SnapPreviewTransitionTests {
    @Test(arguments: [true, false])
    func dismissingQuarterCannotHideNewerMaximizePreview(animated: Bool) async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let preview = PreviewOverlayWindow()
        defer { preview.orderOut(nil) }

        await withCompletedAppKitAnimations {
            preview.present(at: SnapZone.bottomRightQuarter.targetRect(for: screen.visibleFrame))
        }
        await withCompletedAppKitAnimations {
            preview.dismiss()
            preview.present(at: screen.visibleFrame, animated: animated)
        }

        #expect(preview.isVisible)
        #expect(preview.alphaValue > 0.8)
        #expect(preview.frame == screen.visibleFrame)
    }

    @Test func latestDismissalStillClosesAnInterruptedPreview() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let preview = PreviewOverlayWindow()
        defer { preview.orderOut(nil) }

        await withCompletedAppKitAnimations {
            preview.present(at: SnapZone.bottomRightQuarter.targetRect(for: screen.visibleFrame))
        }
        await withCompletedAppKitAnimations {
            preview.dismiss()
            preview.present(at: screen.visibleFrame)
            preview.dismiss()
            preview.dismiss()
        }

        #expect(!preview.isVisible)
        #expect(preview.alphaValue == 0)
    }
}
