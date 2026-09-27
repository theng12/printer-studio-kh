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
/// The worker is idempotent — it only touches a queue when a restriction is
/// actually present — so it cannot loop on its own writes.
enum ShareFix {

    static let label = "com.theng12.printerstudio.sharefix"

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PrinterStudio", isDirectory: true)
    }

    static var workerScript: URL {
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

    // MARK: - Status

    static var isWatcherInstalled: Bool {
        FileManager.default.fileExists(atPath: launchAgent.path)
            && FileManager.default.fileExists(atPath: workerScript.path)
    }

    static var isWatcherLoaded: Bool {
        let uid = getuid()
        let result = Shell.run(Tool.launchctl, ["print", "gui/\(uid)/\(label)"])
        return result.ok
    }

    static func recentLogLines(limit: Int = 40) -> [String] {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n").map(String.init)
        return Array(lines.suffix(limit))
    }

    // MARK: - The worker

    /// Kept as a shell script rather than reimplemented in Swift so the
    /// LaunchAgent can run it with no app process alive.
    static var workerSource: String {
        """
        #!/bin/bash
        # Printer Studio KH — keeps every SHARED queue open to the LAN.
        # Idempotent: only acts when a per-user ACL is actually present.
        LOG="\(logFile.path)"
        mkdir -p "$(dirname "$LOG")"
        ts() { date '+%Y-%m-%d %H:%M:%S'; }

        changed=0
        for P in $(\(Tool.lpstat) -p 2>/dev/null | awk '{print $2}'); do
          [ -n "$P" ] || continue
          attrs=$(\(Tool.ipptool) -tv "ipp://localhost/printers/$P" get-printer-attributes.test 2>/dev/null) || continue
          # only shared queues matter
          echo "$attrs" | grep -q 'printer-is-shared (boolean) = true' || continue
          # only act when a per-user ACL is present
          if echo "$attrs" | grep -qi 'requesting-user-name-allowed'; then
            if \(Tool.lpadmin) -p "$P" -u allow:all 2>>"$LOG"; then
              echo "$(ts) cleared user-ACL on '$P' -> allow:all" >> "$LOG"
              changed=1
            else
              echo "$(ts) FAILED on '$P' (need admin/_lpadmin rights?)" >> "$LOG"
            fi
          fi
        done
        [ "$changed" -eq 0 ] && echo "$(ts) checked: all shared queues already open" >> "$LOG"
        exit 0
        """
    }

    // MARK: - Install / uninstall

    /// Writes the worker + LaunchAgent and loads it. No admin rights needed:
    /// both live in the user's own Library.
    static func installWatcher() -> CommandResult {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(
                at: launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(
                at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try workerSource.write(to: workerScript, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemPath: workerScript.path)
            try launchAgentPlist.write(to: launchAgent, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Could not write the background watcher: \(error.localizedDescription)")
        }

        let uid = getuid()
        _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(uid)/\(label)"])
        let bootstrap = Shell.run(Tool.launchctl, ["bootstrap", "gui/\(uid)", launchAgent.path])
        if !bootstrap.ok {
            let legacy = Shell.run(Tool.launchctl, ["load", "-w", launchAgent.path])
            if !legacy.ok {
                return .failure(
                    "The watcher was written but could not be loaded: \(bootstrap.combined)")
            }
        }
        _ = Shell.run(Tool.launchctl, ["kickstart", "-k", "gui/\(uid)/\(label)"])

        return CommandResult(status: 0, stdout: "Background watcher installed and started.", stderr: "")
    }

    static func uninstallWatcher() -> CommandResult {
        let uid = getuid()
        _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(uid)/\(label)"])

        let fm = FileManager.default
        try? fm.removeItem(at: launchAgent)
        try? fm.removeItem(at: supportDirectory)

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
                <string>/bin/bash</string>
                <string>\(workerScript.path)</string>
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
            try workerSource.write(to: workerScript, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemPath: workerScript.path)
        } catch {
            return .failure("Could not write the worker script: \(error.localizedDescription)")
        }
        return Shell.run(Tool.bash, [workerScript.path])
    }
}

extension FileManager {
    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemPath path: String) throws {
        try setAttributes(attributes, ofItemAtPath: path)
    }
}
