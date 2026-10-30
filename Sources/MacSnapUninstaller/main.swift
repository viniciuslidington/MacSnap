import AppKit
import Darwin
import Foundation
import MacSnapUninstallation

private struct Options {
    var appURL = URL(fileURLWithPath: "/Applications/MacSnap.app")
    var dryRun = false
    var confirmed = false
    var showResult = false
    var parentPID: Int32?

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--dry-run": dryRun = true
            case "--yes": confirmed = true
            case "--show-result": showResult = true
            case "--app":
                index += 1
                guard index < arguments.count, arguments[index].hasPrefix("/") else { throw UninstallError("--app requires an absolute application path.") }
                appURL = URL(fileURLWithPath: arguments[index])
            case "--wait-for-pid":
                index += 1
                guard index < arguments.count, let pid = Int32(arguments[index]), pid > 1, pid != getpid() else {
                    throw UninstallError("Invalid parent process.")
                }
                parentPID = pid
            default: throw UninstallError("Usage: MacSnapUninstaller [--app /Applications/MacSnap.app] [--dry-run] [--yes]")
            }
            index += 1
        }
    }
}

@MainActor private final class NativeUninstallSystem: UninstallSystem {
    let parentPID: Int32?
    private var legacyBuild = false
    init(parentPID: Int32?) { self.parentPID = parentPID }

    private func run(_ executable: String, _ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func processes() throws -> [(Int32, String)] {
        let (status, output) = try run("/bin/ps", ["-axo", "pid=,comm="])
        guard status == 0 else { throw UninstallError("Could not check running applications. Nothing was removed.") }
        return output.split(separator: "\n").compactMap { line in
            let fields = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, let pid = Int32(fields[0]) else { return nil }
            return (pid, String(fields[1]).trimmingCharacters(in: .whitespaces))
        }
    }

    func prepare(_ plan: UninstallPlan) throws {
        if let parentPID {
            if let parent = try processes().first(where: { $0.0 == parentPID }),
               parent.1 != plan.appURL.appendingPathComponent("Contents/MacOS/MacSnap").path {
                throw UninstallError("The process being waited for is not this MacSnap installation.")
            }
            let deadline = Date().addingTimeInterval(30)
            while kill(parentPID, 0) == 0 {
                guard Date() < deadline else { throw UninstallError("MacSnap has not finished quitting. Nothing was removed.") }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        let appPrefix = plan.appURL.path + "/Contents/"
        let updateCache = plan.homeURL.appendingPathComponent("Library/Caches/\(UninstallPlan.bundleIdentifier)").path + "/"
        func hasActiveProcess() throws -> Bool {
            let appRunning = NSRunningApplication.runningApplications(withBundleIdentifier: UninstallPlan.bundleIdentifier)
                .contains { $0.processIdentifier != getpid() && !$0.isTerminated }
            if appRunning { return true }
            return try processes().contains {
                $0.0 != getpid() && ($0.1.hasPrefix(appPrefix) || $0.1.hasPrefix(updateCache))
            }
        }
        let graceDeadline = Date().addingTimeInterval(parentPID == nil ? 0 : 5)
        while try hasActiveProcess() {
            guard Date() < graceDeadline else {
                throw UninstallError("Quit MacSnap and finish any running update before uninstalling. Nothing was removed.")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        if FileManager.default.fileExists(atPath: plan.appURL.path) {
            let data = try Data(contentsOf: plan.appURL.appendingPathComponent("Contents/Info.plist"))
            let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            if info?["MacSnapCleanUninstallVersion"] as? Int == 1 {
                let executable = plan.appURL.appendingPathComponent("Contents/MacOS/MacSnap").path
                let (status, _) = try run(executable, ["--unregister-login-item"])
                guard status == 0 else { throw UninstallError("Could not disable MacSnap's login item. Nothing was removed.") }
            } else { legacyBuild = true }
        }
        if FileManager.default.fileExists(atPath: plan.launchAgentURL.path) {
            let domain = "gui/\(getuid())/\(UninstallPlan.bundleIdentifier)"
            if try run("/bin/launchctl", ["print", domain]).0 == 0 {
                guard try run("/bin/launchctl", ["bootout", domain]).0 == 0 else {
                    throw UninstallError("Could not stop MacSnap's legacy login agent. Nothing was removed.")
                }
            }
        }
    }

    func moveApplicationToTrash(_ appURL: URL) throws {
        try FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
    }

    func clearSystemState(_ plan: UninstallPlan) -> [String] {
        var warnings: [String] = []
        if legacyBuild {
            warnings.append("This older build cannot unregister its modern login item. Remove MacSnap from System Settings > General > Login Items if it is still listed.")
        }
        let id = UninstallPlan.bundleIdentifier
        do {
            // A missing preferences domain is already clean.
            if try run("/usr/bin/defaults", ["read", id]).0 == 0,
               try run("/usr/bin/defaults", ["delete", id]).0 != 0 {
                warnings.append("Could not reset MacSnap preferences.")
            }
            if try run("/usr/bin/defaults", ["-currentHost", "read", id]).0 == 0,
               try run("/usr/bin/defaults", ["-currentHost", "delete", id]).0 != 0 {
                warnings.append("Could not reset MacSnap's settings for this Mac.")
            }
        } catch { warnings.append("Could not reset MacSnap preferences: \(error.localizedDescription)") }
        do {
            if try run("/usr/bin/tccutil", ["reset", "All", id]).0 != 0 {
                warnings.append("macOS could not reset MacSnap permissions. Check Privacy & Security if reinstalling.")
            }
        } catch { warnings.append("Could not reset MacSnap permissions: \(error.localizedDescription)") }
        do {
            let tool = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            if try run(tool, ["-u", plan.appURL.path]).0 != 0 {
                warnings.append("macOS could not clear the old application registration.")
            }
        } catch { warnings.append("Could not clear the application registration: \(error.localizedDescription)") }
        let legacyLog = URL(fileURLWithPath: "/private/tmp/MacSnap.log")
        do {
            if FileManager.default.fileExists(atPath: legacyLog.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: legacyLog.path)
                if attributes[.type] as? FileAttributeType == .typeRegular,
                   (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() {
                    try FileManager.default.removeItem(at: legacyLog)
                }
            }
        } catch { warnings.append("Could not remove MacSnap's legacy log: \(error.localizedDescription)") }
        return warnings
    }
}

@MainActor private func showResult(_ message: String, succeeded: Bool) {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let alert = NSAlert()
    alert.messageText = succeeded ? "MacSnap was uninstalled" : "MacSnap uninstallation needs attention"
    alert.informativeText = message
    alert.alertStyle = succeeded ? .informational : .warning
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

private var options: Options?
do {
    let parsed = try Options(Array(CommandLine.arguments.dropFirst()))
    options = parsed
    let plan = try UninstallPlan(appURL: parsed.appURL)
    print("MacSnap clean uninstall")
    print("Application: \(plan.appURL.path) (moved to Trash)")
    print("Settings and caches to remove:")
    for url in plan.dataURLs { print("  \(url.path)") }
    print("MacSnap's startup registration and privacy permissions will be reset.")
    if parsed.dryRun { print("Preview only. Nothing was changed."); exit(0) }
    if !parsed.confirmed {
        guard isatty(STDIN_FILENO) == 1 else {
            throw UninstallError("Review --dry-run first, then run interactively or pass --yes to confirm removal.")
        }
        print("Type UNINSTALL to remove MacSnap and its settings: ", terminator: "")
        guard readLine() == "UNINSTALL" else { print("Cancelled. Nothing was changed."); exit(0) }
    }
    let report = try plan.execute(using: NativeUninstallSystem(parentPID: parsed.parentPID))
    let message = report.isComplete ? "MacSnap was moved to Trash and its settings, caches and startup entries were removed." : report.warnings.joined(separator: "\n")
    print(message)
    if parsed.showResult { showResult(message, succeeded: report.isComplete) }
    exit(report.isComplete ? 0 : 2)
} catch {
    let message = error.localizedDescription
    FileHandle.standardError.write(Data((message + "\n").utf8))
    if options?.showResult == true { showResult(message, succeeded: false) }
    exit(1)
}
