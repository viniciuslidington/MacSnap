import AppKit
import MacSnapUninstallation
import Sparkle
import Testing
@testable import MacSnap

@MainActor
@Suite(.serialized)
struct UninstallationTests {
    @Test func updaterExposesSparklesCheckPermissionHook() {
        let updater = SparkleAppUpdater(installationIsBusy: { false }, mayCheckForUpdates: { false })
        #expect(updater.responds(to: #selector(SPUUpdaterDelegate.updater(_:mayPerform:))))
    }

    @Test func cleanRemovalPreservesProjectsKeysAndOtherApplications() throws {
        let fixture = try RemovalFixture()
        defer { fixture.cleanUp() }
        let plan = try fixture.plan()
        let report = try plan.execute(using: FixtureRemovalSystem(trash: fixture.trash))
        #expect(report.isComplete)
        #expect(!FileManager.default.fileExists(atPath: fixture.app.path))
        #expect(FileManager.default.fileExists(atPath: fixture.trash.appendingPathComponent("MacSnap.app").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.preferences.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.cache.path))
        for kept in fixture.preserved { #expect(try String(contentsOf: kept, encoding: .utf8) == "keep") }
    }

    @Test func previewDoesNotChangeTheApplicationOrItsSettings() throws {
        let fixture = try RemovalFixture()
        defer { fixture.cleanUp() }
        let plan = try fixture.plan()
        #expect(plan.dataURLs.contains(fixture.preferences))
        #expect(!plan.dataURLs.contains(fixture.preserved[0]))
        #expect(FileManager.default.fileExists(atPath: fixture.app.path))
        #expect(try String(contentsOf: fixture.preferences, encoding: .utf8) == "settings")
    }

    @Test func wrongApplicationIdentityIsRejected() throws {
        let fixture = try RemovalFixture()
        defer { fixture.cleanUp() }
        try fixture.setIdentifier("com.example.OtherApp")
        #expect(throws: (any Error).self) { try fixture.plan() }
        #expect(FileManager.default.fileExists(atPath: fixture.preferences.path))
    }

    @Test func symbolicLinkCannotRedirectCacheRemovalIntoDocuments() throws {
        let fixture = try RemovalFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.removeItem(at: fixture.cache)
        let outside = fixture.home.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let document = outside.appendingPathComponent("important.txt")
        try "keep".write(to: document, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: fixture.cache, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try fixture.plan() }
        #expect(try String(contentsOf: document, encoding: .utf8) == "keep")
    }

    @Test func changedIdentityAfterPreviewCannotBeRemoved() throws {
        let fixture = try RemovalFixture()
        defer { fixture.cleanUp() }
        let plan = try fixture.plan()
        try fixture.setIdentifier("com.example.Replacement")
        #expect(throws: (any Error).self) { try plan.execute(using: FixtureRemovalSystem(trash: fixture.trash)) }
        #expect(FileManager.default.fileExists(atPath: fixture.app.path))
        #expect(FileManager.default.fileExists(atPath: fixture.preferences.path))
    }

    @Test func failedTrashOperationKeepsSettingsAndApplication() throws {
        let fixture = try RemovalFixture()
        defer { fixture.cleanUp() }
        let plan = try fixture.plan()
        let system = FixtureRemovalSystem(trash: fixture.trash, refuseTrash: true)
        #expect(throws: (any Error).self) { try plan.execute(using: system) }
        #expect(FileManager.default.fileExists(atPath: fixture.app.path))
        #expect(FileManager.default.fileExists(atPath: fixture.preferences.path))
    }

    @Test func remainingSettingsCanBeRemovedAfterAppWasDeleted() throws {
        let fixture = try RemovalFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.removeItem(at: fixture.app)
        let report = try fixture.plan().execute(using: FixtureRemovalSystem(trash: fixture.trash))
        #expect(report.isComplete)
        #expect(!FileManager.default.fileExists(atPath: fixture.preferences.path))
    }

    @Test func cancelConfirmationAndUpdateInProgressNeverStartRemoval() throws {
        let fixture = try RemovalFixture()
        defer { fixture.cleanUp() }
        var removed = false
        let cancelled = AppUninstaller(canUninstall: { true }, makePlan: { try fixture.plan() },
            confirm: { _ in false }, remove: { _ in removed = true }, showError: { _ in Issue.record("Unexpected error") })
        cancelled.requestUninstall()
        #expect(!removed)
        #expect(!cancelled.isPreparing)
        var updateBusy = false
        var errorShown = false
        let interrupted = AppUninstaller(canUninstall: { !updateBusy }, makePlan: { try fixture.plan() },
            confirm: { _ in updateBusy = true; return true }, remove: { _ in removed = true }, showError: { _ in errorShown = true })
        interrupted.requestUninstall()
        #expect(errorShown)
        #expect(!removed)
        #expect(!interrupted.isPreparing)
    }

    @Test func menuRoutesUninstallOnlyWhenTheActionIsAvailable() throws {
        var requested = false
        let controller = MenuBarController(onUninstall: { requested = true })
        let status = try #require(controller.statusItem)
        defer { NSStatusBar.system.removeStatusItem(status) }
        let menu = try #require(status.menu)
        let item = try #require(menu.item(withTitle: "Uninstall MacSnap…"))
        #expect(item.isEnabled)
        menu.performActionForItem(at: menu.index(of: item))
        #expect(requested)
        let unavailable = MenuBarController()
        let otherStatus = try #require(unavailable.statusItem)
        defer { NSStatusBar.system.removeStatusItem(otherStatus) }
        #expect(otherStatus.menu?.item(withTitle: "Uninstall MacSnap…")?.isEnabled == false)
    }
}

private final class RemovalFixture {
    let root: URL
    let home: URL
    let applications: URL
    let app: URL
    let trash: URL
    let preferences: URL
    let cache: URL
    let preserved: [URL]

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("macsnap-removal-test-\(UUID().uuidString)").resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        applications = root.appendingPathComponent("Applications")
        app = applications.appendingPathComponent("MacSnap.app")
        trash = root.appendingPathComponent("trash")
        preferences = home.appendingPathComponent("Library/Preferences/com.viniciuslidington.MacSnap.plist")
        cache = home.appendingPathComponent("Library/Caches/com.viniciuslidington.MacSnap")
        preserved = [home.appendingPathComponent("Projects/MacSnap/main.swift"),
                     home.appendingPathComponent(".macsnap-signing/backup.txt"),
                     home.appendingPathComponent("Library/Caches/com.example.OtherApp/data.txt")]
        for directory in [app.appendingPathComponent("Contents"), trash, preferences.deletingLastPathComponent(), cache] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try setIdentifier(UninstallPlan.bundleIdentifier)
        try "settings".write(to: preferences, atomically: true, encoding: .utf8)
        try "cache".write(to: cache.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)
        for url in preserved {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "keep".write(to: url, atomically: true, encoding: .utf8)
        }
    }
    func setIdentifier(_ identifier: String) throws {
        let info = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
    }
    func plan() throws -> UninstallPlan { try UninstallPlan(appURL: app, homeURL: home, applicationDirectories: [applications]) }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@MainActor private struct FixtureRemovalSystem: UninstallSystem {
    let trash: URL
    var refuseTrash = false
    func prepare(_ plan: UninstallPlan) throws {}
    func moveApplicationToTrash(_ appURL: URL) throws {
        if refuseTrash { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.moveItem(at: appURL, to: trash.appendingPathComponent("MacSnap.app"))
    }
    func clearSystemState(_ plan: UninstallPlan) -> [String] { [] }
}
