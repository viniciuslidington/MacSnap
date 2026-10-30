import AppKit
import Sparkle

/// Owns the SDK and its dockless presentation; no window-geometry code depends on it.
@MainActor
final class SparkleAppUpdater: NSObject, AppUpdating, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    private var availabilityObservation: NSKeyValueObservation?
    private var pendingVersion: String?
    private let installationIsBusy: () -> Bool
    private let scheduler: any ActionScheduling
    private var terminationCheck: (any ScheduledAction)?
    private var resumeTermination: (() -> Void)?
    private var terminationGeneration: UInt64 = 0
    var onChange: (() -> Void)?

    init(
        installationIsBusy: @escaping () -> Bool,
        scheduler: (any ActionScheduling)? = nil
    ) {
        self.installationIsBusy = installationIsBusy
        self.scheduler = scheduler ?? MainActorScheduler.shared
        super.init()
        let bundle = Bundle.main
        // Never start networking for unbundled tests or an unconfigured release.
        guard bundle.bundleURL.pathExtension == "app",
              let urlString = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: urlString), url.scheme == "https", url.host != nil,
              let encodedKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: encodedKey)?.count == 32 else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        self.controller = controller
        availabilityObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.onChange?() }
        }
        controller.startUpdater()
    }

    var presentation: UpdatePresentation {
        UpdatePresentation(isAvailable: controller != nil,
                           canCheck: controller?.updater.canCheckForUpdates ?? false,
                           pendingVersion: pendingVersion)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue; onChange?() }
    }

    var automaticallyInstallsUpdates: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue; onChange?() }
    }

    func checkForUpdates() {
        guard presentation.canCheck else { return }
        controller?.checkForUpdates(nil)
    }

    func deferTermination(resume: @escaping () -> Void) -> Bool {
        guard installationIsBusy() else {
            terminationGeneration &+= 1
            terminationCheck?.cancel()
            terminationCheck = nil
            resumeTermination = nil
            return false
        }
        // Multiple termination requests share one pending reply.
        resumeTermination = resume
        if terminationCheck == nil { scheduleTerminationCheck() }
        return true
    }

    private func scheduleTerminationCheck() {
        let generation = terminationGeneration
        terminationCheck = scheduler.schedule(after: 0.1) { [weak self] in
            guard let self, self.terminationGeneration == generation,
                  self.resumeTermination != nil else { return }
            self.terminationCheck = nil
            if self.installationIsBusy() {
                self.scheduleTerminationCheck()
            } else {
                let resume = self.resumeTermination
                self.resumeTermination = nil
                resume?()
            }
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Scheduled offers live in the menu; explicit checks still use Sparkle's UI.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        pendingVersion = update.displayVersionString
        onChange?()
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingVersion = nil
        onChange?()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        pendingVersion = nil
        onChange?()
    }
}
