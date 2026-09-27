import Foundation

// MARK: - Command results

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var ok: Bool { status == 0 }

    /// Human-readable output for the Activity log.
    var combined: String {
        let s = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return e }
        if e.isEmpty { return s }
        return s + "\n" + e
    }

    static func failure(_ message: String) -> CommandResult {
        CommandResult(status: -1, stdout: "", stderr: message)
    }
}

// MARK: - Tool discovery

/// Locates the system binaries we depend on. The app must not rely on the
/// user's PATH: a bundled .app launched from Finder inherits a minimal
/// environment, and on macOS some of these live in /usr/sbin.
enum Tool {
    private static let searchPaths = [
        "/usr/bin", "/usr/sbin", "/bin", "/sbin",
        "/opt/homebrew/bin", "/usr/local/bin",
    ]

    static func path(_ name: String) -> String {
        for dir in searchPaths {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/bin/\(name)"
    }

    static var lpstat: String { path("lpstat") }
    static var lpadmin: String { path("lpadmin") }
    static var lpoptions: String { path("lpoptions") }
    static var lp: String { path("lp") }
    static var lpinfo: String { path("lpinfo") }
    static var cupsConfig: String { path("cups-config") }
    static var lprm: String { path("lprm") }
    static var ipptool: String { path("ipptool") }
    static var cupsctl: String { path("cupsctl") }
    static var osascript: String { path("osascript") }
    static var ioreg: String { path("ioreg") }
    static var launchctl: String { path("launchctl") }
    static var bash: String { path("bash") }
    static var awk: String { path("awk") }
    static var open: String { path("open") }
}

// MARK: - Shell

enum Shell {
    /// Runs a binary and waits for it. Safe to call from a background thread.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String] = []) -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            return .failure("Missing tool: \(launchPath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return .failure("Could not run \(launchPath): \(error.localizedDescription)")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Runs a shell script as the administrator. macOS shows its own password
    /// dialog — this is what keeps the app terminal-free.
    ///
    /// The script is staged to a temp file and executed by path so that no
    /// quoting of the script body is needed.
    @discardableResult
    static func runAsAdministrator(_ script: String, prompt: String? = nil) -> CommandResult {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("printer-studio-\(UUID().uuidString).sh")

        let body = "#!/bin/bash\nset -uo pipefail\n" + script + "\n"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Could not stage the privileged script: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: url) }

        // Build: do shell script "/bin/bash '<path>'" with administrator privileges
        var appleScript = "do shell script \"/bin/bash '\(url.path)'\" with administrator privileges"
        if let prompt {
            let escaped = prompt.replacingOccurrences(of: "\"", with: "\\\"")
            appleScript += " with prompt \"\(escaped)\""
        }

        let result = run(Tool.osascript, ["-e", appleScript])

        // -128 is AppleScript's "user cancelled".
        if result.status != 0 && (result.stderr.contains("-128") || result.stderr.contains("User canceled")) {
            return CommandResult(status: -128, stdout: "", stderr: "Cancelled — no changes were made.")
        }
        return result
    }
}
