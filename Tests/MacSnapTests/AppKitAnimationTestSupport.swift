import AppKit

/// Wait for native animation completion, including work enqueued by nested groups.
@MainActor
func withCompletedAppKitAnimations(_ changes: () -> Void) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        NSAnimationContext.runAnimationGroup({ _ in
            changes()
        }, completionHandler: {
            // Dismissal handlers enqueue their final orderOut on the main queue.
            DispatchQueue.main.async { continuation.resume() }
        })
    }
}
