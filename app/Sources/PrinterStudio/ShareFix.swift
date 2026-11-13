import Foundation

/// The "Printer Share Fix", folded into the app.
///
/// macOS pins a per-printer user ACL onto shared queues, which is what makes
/// another Mac on the LAN see "Job held for authentication". This service
/// keeps every *shared* queue open with `lpadmin -u allow:all`:
///
///   * once, on demand (the "Fix now" button), and
///   * continuously, inside the AirPrint helper job, which runs both passes.
///
/// The work runs inside `Printer Studio KH Helper.app`, so Activity Monitor and
/// Login Items show the app rather than an invisible bash script.
enum ShareFix {

    /// The share-fix agent older builds wrote. The pass now runs inside the
    /// AirPrint helper job, so Login Items shows one helper row; this agent is
    /// booted out and retired to `_trash` on upgrade.
    static let legacyLabel = "com.theng12.printerstudio.sharefix"
    static let helperBundleName = "Printer Studio KH Helper"
    static let helperIdentifier = "com.theng12.printerstudio.helper"
    static let usbHelperBundleName = "Printer Studio KH USB Helper"

    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["PRINTER_STUDIO_SUPPORT_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PrinterStudio", isDirectory: true)
    }

    /// A copy older builds put here. Nothing new is written to it: the helper now
    /// runs from inside the app bundle so deleting the app deletes the helper.
    static var legacyHelperApp: URL {
        supportDirectory.appendingPathComponent("\(helperBundleName).app", isDirectory: true)
    }

    static var legacyHelperExecutable: URL {
        legacyHelperApp.appendingPathComponent("Contents/MacOS/\(helperBundleName)", isDirectory: false)
    }

    /// The executable the launchd jobs run: the helper inside the app bundle, so
    /// the two cannot drift apart and nothing outlives the bundle. The support
    /// copy is only a fallback for a build or tool with no bundle around it.
    static var helperExecutable: URL {
        if let bundled = bundledHelperApp {
            return URL(fileURLWithPath: bundled, isDirectory: true)
                .appendingPathComponent("Contents/MacOS/\(helperBundleName)", isDirectory: false)
        }
        return legacyHelperExecutable
    }

    /// The shell worker used before 1.0.15. Kept so an upgrade can retire it.
    static var legacyWorkerScript: URL {
        supportDirectory.appendingPathComponent("keep-shared-queues-open.sh")
    }

    /// The retired agent's plist. In test mode it lives in the scratch support
    /// directory so the real installation is never touched.
    static var legacyLaunchAgent: URL {
        if DriverInstaller.isTestMode {
            return supportDirectory
                .appendingPathComponent("LaunchAgents/\(legacyLabel).plist", isDirectory: false)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyLabel).plist", isDirectory: false)
    }

    static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PrinterStudio", isDirectory: true)
            .appendingPathComponent("share-fix.log", isDirectory: false)
    }

    // MARK: - Bundled helper

    /// Finds a helper bundle shipped inside the app, with checkout fallbacks so
    /// the standalone report tool works too. The test suite can override the
    /// user helper with `PRINTER_STUDIO_BUNDLED_HELPER`.
    static func bundledHelper(named name: String) -> String? {
        let fileManager = FileManager.default
        if name == helperBundleName,
           let override = ProcessInfo.processInfo.environment["PRINTER_STUDIO_BUNDLED_HELPER"] {
            return fileManager.fileExists(atPath: override) ? override : nil
        }
        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL {
            directories.append(resources)
        }
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        directories.append(executableDirectory
            .appendingPathComponent("Printer Studio KH.app/Contents/Resources"))
        directories.append(executableDirectory
            .appendingPathComponent("../dist/Printer Studio KH.app/Contents/Resources"))

        for directory in directories {
            let candidate = directory.appendingPathComponent("\(name).app").path
            if fileManager.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    static var bundledHelperApp: String? { bundledHelper(named: helperBundleName) }

    /// Makes the bundled helper the one the jobs run, and retires any copy an
    /// older build left in the support directory so no second runner survives.
    @discardableResult
    static func installHelperBundle() -> Bool {
        guard let source = bundledHelperApp else { return false }
        _ = moveToTrash(legacyHelperApp.path)
        return FileManager.default.fileExists(atPath: source)
    }

    private static var trashDirectory: URL {
        supportDirectory.appendingPathComponent("_trash", isDirectory: true)
    }

    /// Moves a file or bundle into `_trash` under a dated name and returns the
    /// new path. Nothing installed is ever deleted outright.
    @discardableResult
    static func moveToTrash(_ path: String) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = trashDirectory
            .appendingPathComponent("\(name).\(stamp).\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
            try fileManager.moveItem(atPath: path, toPath: destination.path)
            return destination.path
        } catch {
            return nil
        }
    }

    // MARK: - Status

    /// Both the watcher and the advertisement are the one helper job.
    static var isWatcherInstalled: Bool {
        FileManager.default.fileExists(atPath: DriverInstaller.airPrintAgentPath)
            && FileManager.default.fileExists(atPath: helperExecutable.path)
    }

    static var isWatcherLoaded: Bool {
        let uid = getuid()
        let result = Shell.run(Tool.launchctl, ["print", "gui/\(uid)/\(DriverInstaller.airPrintLabel)"])
        return result.ok
    }

    static func recentLogLines(limit: Int = 40) -> [String] {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n").map(String.init)
        return Array(lines.suffix(limit))
    }

    // MARK: - Install / uninstall

    /// Boots out the share-fix agent older builds wrote and retires its plist,
    /// so an upgrade ends with one helper row. Never deletes: the plist goes
    /// to the app's support `_trash`.
    @discardableResult
    static func retireLegacyAgent() -> Bool {
        if !DriverInstaller.isTestMode {
            _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(getuid())/\(legacyLabel)"])
        }
        if FileManager.default.fileExists(atPath: legacyLaunchAgent.path),
           moveToTrash(legacyLaunchAgent.path) == nil {
            return false
        }
        return true
    }

    /// Installs the one helper job. Its `all` mode keeps shared queues open
    /// and advertises every shared queue, so there is no second LaunchAgent.
    static func installWatcher() -> CommandResult {
        // The watcher shares the one helper job with the AirPrint bridge, but
        // installing it must not switch Printer Sharing on: that is a separate,
        // deliberate action on the Sharing page.
        let result = DriverInstaller.installAirPrintBridge(prepareSharing: {
            CommandResult(status: 0, stdout: "Printer Sharing left as it is.", stderr: "")
        })
        guard result.ok else { return result }
        return CommandResult(
            status: 0, stdout: "Background watcher installed and started.", stderr: "")
    }

    /// Upgrades an older install: the share-fix agent is replaced by the one
    /// combined helper job. Runs at app launch and needs no password.
    @discardableResult
    static func migrateWatcherIfNeeded() -> CommandResult {
        guard !DriverInstaller.isTestMode else {
            return CommandResult(status: 0, stdout: "Background watcher migration skipped in test mode.", stderr: "")
        }
        guard FileManager.default.fileExists(atPath: legacyLaunchAgent.path) else {
            return CommandResult(status: 0, stdout: "Background watcher is up to date.", stderr: "")
        }
        if !DriverInstaller.isAirPrintInstalled {
            let installed = DriverInstaller.installAirPrintBridge()
            guard installed.ok else { return installed }
        }
        guard retireLegacyAgent() else {
            return .failure("Could not move the old background watcher to _trash. Check file permissions and try again.")
        }
        return CommandResult(
            status: 0, stdout: "Background watcher updated: one helper runs both jobs.", stderr: "")
    }

    /// Boots a job out and back in.
    ///
    /// launchd finishes unloading a booted-out job asynchronously (about 0.2 s
    /// here), so bootstrapping straight away can fail with an I/O error and
    /// leave the job off. Wait for the old job to go, then retry.
    static func reloadJob(label: String, plistPath: String,
                          started: String, failure: String) -> CommandResult {
        let uid = getuid()
        _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(uid)/\(label)"])
        let gone = Date().addingTimeInterval(5)
        while jobLoaded(label) && Date() < gone { Thread.sleep(forTimeInterval: 0.1) }
        var lastFailure = ""
        for attempt in 0..<3 {
            let bootstrap = Shell.run(Tool.launchctl, ["bootstrap", "gui/\(uid)", plistPath])
            if bootstrap.ok {
                _ = Shell.run(Tool.launchctl, ["kickstart", "-k", "gui/\(uid)/\(label)"])
                let ready = Date().addingTimeInterval(3)
                while !jobLoaded(label) && Date() < ready { Thread.sleep(forTimeInterval: 0.1) }
                if jobLoaded(label) { return CommandResult(status: 0, stdout: started, stderr: "") }
            }
            lastFailure = bootstrap.combined
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.4) }
        }
        let legacy = Shell.run(Tool.launchctl, ["load", "-w", plistPath])
        if legacy.ok, jobLoaded(label) {
            return CommandResult(status: 0, stdout: started, stderr: "")
        }
        return .failure("\(failure): \(lastFailure)")
    }

    private static func jobLoaded(_ label: String) -> Bool {
        Shell.run(Tool.launchctl, ["print", "gui/\(getuid())/\(label)"]).ok
    }

    /// Stops the one helper job. The share fix and the advertisement share a
    /// process, so removing either removes both.
    static func uninstallWatcher() -> CommandResult {
        let removed = DriverInstaller.removeAirPrintBridge()
        guard removed.ok else { return removed }
        return CommandResult(
            status: 0,
            stdout: "Background watcher removed. Printer settings already applied were left as-is.",
            stderr: "")
    }

    // MARK: - Fix now

    /// Runs the worker immediately, regardless of whether the watcher exists.
    static func fixNow() -> CommandResult {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(
                at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .failure("Could not prepare the worker: \(error.localizedDescription)")
        }
        if !fm.fileExists(atPath: helperExecutable.path) {
            guard installHelperBundle() else {
                return .failure("The Printer Studio KH Helper bundle is missing from this build.")
            }
        }
        return Shell.run(helperExecutable.path, ["sharefix"])
    }
}

extension FileManager {
    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemPath path: String) throws {
        try setAttributes(attributes, ofItemAtPath: path)
    }
}
