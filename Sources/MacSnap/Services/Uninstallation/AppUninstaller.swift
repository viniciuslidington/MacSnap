import AppKit
import MacSnapUninstallation
import ServiceManagement

@MainActor
final class AppUninstaller {
    private(set) var isPreparing = false
    private let canUninstall: () -> Bool
    private let makePlan: () throws -> UninstallPlan
    private let confirm: (UninstallPlan) -> Bool
    private let remove: (UninstallPlan) throws -> Void
    private let showError: (Error) -> Void

    init(
        canUninstall: @escaping () -> Bool,
        makePlan: @escaping () throws -> UninstallPlan = { try UninstallPlan(appURL: Bundle.main.bundleURL) },
        confirm: ((UninstallPlan) -> Bool)? = nil,
        remove: ((UninstallPlan) throws -> Void)? = nil,
        showError: ((Error) -> Void)? = nil
    ) {
        self.canUninstall = canUninstall
        self.makePlan = makePlan
        self.confirm = confirm ?? Self.confirmRemoval
        self.remove = remove ?? Self.launchUninstaller
        self.showError = showError ?? Self.presentError
    }

    var isAvailable: Bool {
        Bundle.main.bundleIdentifier == UninstallPlan.bundleIdentifier &&
            FileManager.default.isExecutableFile(atPath: Self.helperURL.path)
    }

    func requestUninstall() {
        guard !isPreparing else { return }
        do {
            guard canUninstall() else { throw UninstallError("Finish or dismiss the current update before uninstalling MacSnap.") }
            let plan = try makePlan()
            guard confirm(plan) else { return }
            // A scheduled update may have started while the confirmation dialog was open.
            guard canUninstall() else { throw UninstallError("An update is now in progress. Finish it before uninstalling MacSnap.") }
            try plan.validate()
            isPreparing = true
            try remove(plan)
        } catch {
            isPreparing = false
            showError(error)
        }
    }

    private static var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MacSnapUninstaller") }

    private static func confirmRemoval(_ plan: UninstallPlan) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Uninstall MacSnap?"
        alert.informativeText = "MacSnap will close and move to Trash. Its settings, caches, startup entries and privacy permissions will be removed. Your documents will be kept."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Uninstall")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private static func launchUninstaller(_ plan: UninstallPlan) throws {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw UninstallError("This build has no clean uninstaller. Use a packaged MacSnap release.")
        }
        try unregisterLoginItem()
        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--app", plan.appURL.path, "--yes", "--wait-for-pid", String(getpid()), "--show-result"]
        // The helper presents its result after this app quits; leave no uninstall log behind.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        NSApp.terminate(nil)
    }

    static func unregisterLoginItem() throws {
        let status = SMAppService.mainApp.status
        if status == .enabled || status == .requiresApproval { try SMAppService.mainApp.unregister() }
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "MacSnap could not be uninstalled"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
