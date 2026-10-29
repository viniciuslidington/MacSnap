import Foundation

/// Cancellation belongs to the operation that requested delayed work.
@MainActor
public protocol ScheduledAction: AnyObject {
    func cancel()
}

/// Internal time seam shared by native interaction modules and deterministic tests.
/// Actions are enqueued, never invoked inline, even for a zero delay. Cancellation
/// prevents future delivery; owners also validate their lifetime when work runs.
@MainActor
public protocol ActionScheduling: AnyObject {
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledAction
}

/// Runs delayed work on the UI actor without retaining an interaction's owner.
@MainActor
public final class MainActorScheduler: ActionScheduling {
    public static let shared = MainActorScheduler()

    public init() {}

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledAction {
        precondition(delay.isFinite && delay >= 0, "Delay must be finite and nonnegative")
        let task = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskScheduledAction(task: task)
    }
}

@MainActor
private final class TaskScheduledAction: ScheduledAction {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}
