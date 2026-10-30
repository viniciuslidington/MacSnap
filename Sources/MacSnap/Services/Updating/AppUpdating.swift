import Foundation

/// The app/menu seam. Download trust, versioning and replacement belong to Sparkle.
@MainActor
protocol AppUpdating: AnyObject {
    var presentation: UpdatePresentation { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyInstallsUpdates: Bool { get set }
    var onChange: (() -> Void)? { get set }
    func checkForUpdates()
    /// Return true only when the caller must wait for resume before terminating.
    func deferTermination(resume: @escaping () -> Void) -> Bool
}

struct UpdatePresentation: Equatable {
    var isAvailable = false
    var canCheck = false
    var pendingVersion: String?
    var isUninstallSafe = true
}

/// Unbundled/development launches and menu tests need no updater or network access.
@MainActor
final class UnavailableAppUpdater: AppUpdating {
    let presentation = UpdatePresentation()
    var automaticallyChecksForUpdates = false
    var automaticallyInstallsUpdates = false
    var onChange: (() -> Void)?
    func checkForUpdates() {}
    func deferTermination(resume: @escaping () -> Void) -> Bool { false }
}
