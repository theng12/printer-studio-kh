import Foundation

/// The "Printer Share Fix", folded into the app.
///
/// macOS pins a per-printer user ACL onto shared queues, which is what makes
/// another Mac on the LAN see "Job held for authentication". This service
/// keeps every *shared* queue open with `lpadmin -u allow:all`:
///
///   * once, on demand (the "Fix now" button), and
///   * continuously, via a per-user LaunchAgent that re-checks every 60s.
///
/// The work runs inside `Printer Studio KH Helper.app`, so Activity Monitor and
/// Login Items show the app rather than an invisible bash script.
enum ShareFix {

    static let label = "com.theng12.printerstudio.sharefix"
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

    static var helperApp: URL {
        supportDirectory.appendingPathComponent("\(helperBundleName).app", isDirectory: true)
    }

    static var helperExecutable: URL {
        helperApp.appendingPathComponent("Contents/MacOS/\(helperBundleName)", isDirectory: false)
    }

    /// The shell worker used before 1.0.15. Kept so an upgrade can retire it.
    static var legacyWorkerScript: URL {
        supportDirectory.appendingPathComponent("keep-shared-queues-open.sh")
    }

    static var launchAgent: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist", isDirectory: false)
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

    /// Copies the bundled helper into the user support directory, retaining any
    /// previous copy in `_trash`.
    @discardableResult
    static func installHelperBundle() -> Bool {
        guard let source = bundledHelperApp else { return false }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            _ = moveToTrash(helperApp.path)
            try fileManager.copyItem(atPath: source, toPath: helperApp.path)
            return fileManager.fileExists(atPath: helperExecutable.path)
        } catch {
            return false
        }
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

    static var isWatcherInstalled: Bool {
        FileManager.default.fileExists(atPath: launchAgent.path)
            && FileManager.default.fileExists(atPath: helperExecutable.path)
    }

    static var isWatcherLoaded: Bool {
        let uid = getuid()
        let result = Shell.run(Tool.launchctl, ["print", "gui/\(uid)/\(label)"])
        return result.ok
    }

    static var installedAgentPointsAtHelper: Bool {
        guard let data = try? Data(contentsOf: launchAgent),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { return false }
        return arguments == [helperExecutable.path, "sharefix"]
    }

    static func recentLogLines(limit: Int = 40) -> [String] {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n").map(String.init)
        return Array(lines.suffix(limit))
    }

    // MARK: - Install / uninstall

    /// Writes the helper + LaunchAgent and loads it. No admin rights needed:
    /// both live in the user's own Library.
    static func installWatcher() -> CommandResult {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(
                at: launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(
                at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .failure("Could not write the background watcher: \(error.localizedDescription)")
        }
        guard installHelperBundle() else {
            return .failure("The Printer Studio KH Helper bundle is missing from this build.")
        }
        _ = moveToTrash(legacyWorkerScript.path)
        do {
            try launchAgentPlist.write(to: launchAgent, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Could not write the background watcher: \(error.localizedDescription)")
        }
        return reloadAgent(failure: "The watcher was written but could not be loaded")
    }

    /// Upgrades an older install whose agent still runs the shell worker.
    /// Runs at app launch and needs no administrator password.
    @discardableResult
    static func migrateWatcherIfNeeded() -> CommandResult {
        guard ProcessInfo.processInfo.environment["PRINTER_STUDIO_AIRPRINT_TEST"] != "1" else {
            return CommandResult(status: 0, stdout: "Background watcher migration skipped in test mode.", stderr: "")
        }
        guard FileManager.default.fileExists(atPath: launchAgent.path) else {
            return CommandResult(status: 0, stdout: "Background watcher is off.", stderr: "")
        }
        let legacyPresent = FileManager.default.fileExists(atPath: legacyWorkerScript.path)
        let helperPresent = FileManager.default.fileExists(atPath: helperExecutable.path)
        guard !helperPresent || !installedAgentPointsAtHelper || legacyPresent else {
            return CommandResult(status: 0, stdout: "Background watcher is up to date.", stderr: "")
        }
        guard installHelperBundle() else {
            return .failure("Could not install the Printer Studio KH Helper bundle.")
        }
        _ = moveToTrash(legacyWorkerScript.path)
        do {
            try launchAgentPlist.write(to: launchAgent, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Could not update the background watcher: \(error.localizedDescription)")
        }
        return reloadAgent(failure: "The watcher was updated but could not be loaded")
    }

    private static func reloadAgent(failure: String) -> CommandResult {
        reloadJob(label: label, plistPath: launchAgent.path,
                  started: "Background watcher installed and started.", failure: failure)
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

    static func uninstallWatcher() -> CommandResult {
        let uid = getuid()
        _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(uid)/\(label)"])

        if moveToTrash(launchAgent.path) == nil,
           FileManager.default.fileExists(atPath: launchAgent.path) {
            return .failure("Could not move the background watcher to _trash. Check file permissions and try again.")
        }
        _ = moveToTrash(legacyWorkerScript.path)

        return CommandResult(
            status: 0,
            stdout: "Background watcher removed. Printer settings already applied were left as-is.",
            stderr: "")
    }

    private static var launchAgentPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(helperExecutable.path)</string>
                <string>sharefix</string>
            </array>
            <key>AssociatedBundleIdentifiers</key>
            <array>
                <string>\(helperIdentifier)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>60</integer>
            <key>StandardErrorPath</key>
            <string>\(logFile.deletingLastPathComponent().path)/share-fix.err.log</string>
        </dict>
        </plist>
        """
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
