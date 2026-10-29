import AppKit
import ApplicationServices
import Testing
@testable import MacSnap

@MainActor
struct AccessibilityServiceTests {
    @Test func nativeElementReadersRejectUnexpectedCFTypes() throws {
        let element = AXUIElementCreateSystemWide()
        let parsed = try #require(AccessibilityService.element(from: element))
        #expect(CFEqual(element, parsed))
        #expect(AccessibilityService.element(from: "wrong type" as CFString) == nil)
        #expect(AccessibilityService.element(from: nil) == nil)
        #expect(AccessibilityService.elements(from: element).isEmpty)

        var callbacks = kCFTypeArrayCallBacks
        let array = CFArrayCreateMutable(kCFAllocatorDefault, 0, &callbacks)!
        CFArrayAppendValue(array, Unmanaged.passUnretained(element).toOpaque())
        let invalid: CFBoolean = kCFBooleanTrue
        CFArrayAppendValue(array, Unmanaged.passUnretained(invalid).toOpaque())
        let windows = AccessibilityService.elements(from: array)
        #expect(windows.count == 1)
        #expect(CFEqual(windows[0], element))
    }

    @Test func activationObserverIsRemovedWhenTheModuleIsReleased() {
        let center = RecordingNotificationCenter()
        var service: AccessibilityService? = AccessibilityService(notificationCenter: center)
        weak var weakService = service
        withExtendedLifetime(service) {
            #expect(center.removals == 0)
        }
        service = nil
        #expect(weakService == nil)
        #expect(center.removals == 1)
    }
}

/// NotificationCenter can invoke removal from any releasing thread.
private final class RecordingNotificationCenter: NotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var removalCount = 0
    var removals: Int { lock.withLock { removalCount } }

    override func removeObserver(_ observer: Any) {
        lock.withLock { removalCount += 1 }
        super.removeObserver(observer)
    }
}
