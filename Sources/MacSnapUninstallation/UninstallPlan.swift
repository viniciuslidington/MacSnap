import Foundation

/// A bounded removal plan. Source checkouts, signing keys and unrelated app data are never searched.
public struct UninstallPlan {
    public static let bundleIdentifier = "com.viniciuslidington.MacSnap"
    public let appURL: URL
    public let homeURL: URL
    public let dataURLs: [URL]
    public var launchAgentURL: URL { homeURL.appendingPathComponent("Library/LaunchAgents/\(Self.bundleIdentifier).plist") }
    private let applicationDirectories: [URL]

    public init(
        appURL: URL,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationDirectories: [URL]? = nil
    ) throws {
        let resolvedHome = homeURL.standardizedFileURL.resolvingSymlinksInPath()
        self.homeURL = resolvedHome
        self.applicationDirectories = applicationDirectories ?? [
            URL(fileURLWithPath: "/Applications"), homeURL.appendingPathComponent("Applications")
        ]
        self.appURL = appURL.standardizedFileURL
        let id = Self.bundleIdentifier
        let relativePaths = [
            "Library/Preferences/\(id).plist", "Library/Caches/\(id)",
            "Library/Application Support/\(id)", "Library/Application Support/MacSnap",
            "Library/HTTPStorages/\(id)", "Library/WebKit/\(id)",
            "Library/Saved Application State/\(id).savedState", "Library/Application Scripts/\(id)",
            "Library/Logs/\(id)", "Library/Logs/MacSnap", "Library/LaunchAgents/\(id).plist"
        ]
        var targets = relativePaths.map { resolvedHome.appendingPathComponent($0) }
        let byHost = resolvedHome.appendingPathComponent("Library/Preferences/ByHost")
        if let entries = try? FileManager.default.contentsOfDirectory(at: byHost, includingPropertiesForKeys: nil) {
            targets += entries.filter {
                let name = $0.lastPathComponent
                guard name.hasPrefix(id + "."), name.hasSuffix(".plist") else { return false }
                return UUID(uuidString: String(name.dropFirst(id.count + 1).dropLast(6))) != nil
            }
        }
        self.dataURLs = targets
        try validate()
    }

    public func validate() throws {
        let allowed = applicationDirectories.map {
            $0.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent("MacSnap.app")
        }
        guard allowed.contains(appURL) else {
            throw UninstallError("Move MacSnap to /Applications or your Applications folder before uninstalling.")
        }
        try rejectSymbolicLinks(to: appURL, from: appURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: appURL.path) {
            let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
            try rejectSymbolicLinks(to: infoURL, from: appURL)
            let data = try Data(contentsOf: infoURL)
            let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            guard info?["CFBundleIdentifier"] as? String == Self.bundleIdentifier else {
                throw UninstallError("The selected application is not MacSnap. Nothing was removed.")
            }
        }
        for target in dataURLs { try rejectSymbolicLinks(to: target, from: homeURL) }
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            let data = try Data(contentsOf: launchAgentURL)
            let agent = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            let program = (agent?["ProgramArguments"] as? [String])?.first
            let allowedPrograms = allowed.map { $0.appendingPathComponent("Contents/MacOS/MacSnap").path }
            guard agent?["Label"] as? String == Self.bundleIdentifier,
                  program.map(allowedPrograms.contains) == true else {
                throw UninstallError("The legacy startup file does not belong to MacSnap. Nothing was removed.")
            }
        }
    }

    /// Validate again after confirmation and immediately before each filesystem removal.
    @MainActor public func execute(using system: any UninstallSystem) throws -> UninstallReport {
        try validate()
        try system.prepare(self)
        try validate()
        if FileManager.default.fileExists(atPath: appURL.path) { try system.moveApplicationToTrash(appURL) }
        var warnings = system.clearSystemState(self)
        var removed: [URL] = []
        for target in dataURLs {
            do {
                try rejectSymbolicLinks(to: target, from: homeURL)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                    removed.append(target)
                }
            } catch { warnings.append("Could not remove \(target.path): \(error.localizedDescription)") }
        }
        return UninstallReport(removedDataURLs: removed, warnings: warnings)
    }

    private func rejectSymbolicLinks(to target: URL, from root: URL) throws {
        let rootParts = root.standardizedFileURL.pathComponents
        let parts = target.standardizedFileURL.pathComponents
        guard parts.starts(with: rootParts), parts.count > rootParts.count else {
            throw UninstallError("Refusing to remove a path outside MacSnap's data folders.")
        }
        var current = root
        // Include the base: a symlinked Library must not redirect the removal elsewhere.
        for component in parts.dropFirst(rootParts.count) {
            current.appendPathComponent(component)
            if let type = try? FileManager.default.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType,
               type == .typeSymbolicLink {
                throw UninstallError("Refusing to follow a symbolic link: \(current.path)")
            }
        }
    }
}

@MainActor public protocol UninstallSystem {
    func prepare(_ plan: UninstallPlan) throws
    func moveApplicationToTrash(_ appURL: URL) throws
    func clearSystemState(_ plan: UninstallPlan) -> [String]
}

public struct UninstallReport {
    public let removedDataURLs: [URL]
    public let warnings: [String]
    public var isComplete: Bool { warnings.isEmpty }
}

public struct UninstallError: LocalizedError {
    private let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
