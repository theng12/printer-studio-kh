import Foundation
import Darwin

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

// MARK: - Free space

/// Says how much room is left when a command fails because the disk is full, so
/// the message names the number instead of leaving the person to guess.
enum DiskSpace {
    static func freeBytes(at path: String = NSHomeDirectory()) -> Int64? {
        (try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    static func describe(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Only a full-disk failure gains the number; every other message is unchanged.
    static func explain(_ message: String, freeBytes: Int64?) -> String {
        guard let freeBytes,
              message.range(of: "no space left on device", options: .caseInsensitive) != nil
        else { return message }
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
            + " \(describe(freeBytes)) free."
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
    /// Validates a PPD before we install it, so a bad entry cannot leave a
    /// printer unusable.
    static var cupstestppd: String { path("cupstestppd") }
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
    static var pgrep: String { path("pgrep") }
    static var open: String { path("open") }
}

// MARK: - Shell

/// Output collected while a command runs, so a stopped command still answers
/// with what it had printed.
private final class PipeText: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func collect(from handle: FileHandle) {
        while let chunk = try? handle.read(upToCount: 65536), !chunk.isEmpty {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A cancel token for one running action. `perform` opens a scope per action;
/// Escape closes it and the child is stopped the way the ceiling stops one.
final class ShellCancel: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock(); flag = true; lock.unlock()
    }
}

enum Shell {
    /// The cancel scope of the action currently running, or nil between actions.
    /// Existing callers pass nothing and keep their exact behaviour; only a
    /// scope opened by `perform` makes a run cancellable.
    private static let scopeLock = NSLock()
    private static var scopedToken: ShellCancel?

    static func beginCancelScope(_ token: ShellCancel) {
        scopeLock.lock(); scopedToken = token; scopeLock.unlock()
    }

    static func endCancelScope(_ token: ShellCancel) {
        scopeLock.lock(); if scopedToken === token { scopedToken = nil }; scopeLock.unlock()
    }

    /// Asks the running action to stop. Returns a plain refusal when nothing is
    /// running; the scope is closed when the action ends, so a finished action
    /// cannot be cancelled again.
    static func cancelCurrent() -> String? {
        scopeLock.lock()
        let token = scopedToken
        scopeLock.unlock()
        guard let token else {
            return "Nothing is running to cancel right now."
        }
        token.cancel()
        return nil
    }

    /// Runs a binary and waits for it, but never past its own ceiling: a wedged
    /// cupsd, a stuck launchd or an unanswered password prompt would otherwise
    /// leave the action — and every control behind `busy` — hanging for good.
    /// A cancelled run ends the same way, with its own distinct outcome.
    /// Safe to call from a background thread.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String] = [],
                    timeout: TimeInterval = 120, cancel: ShellCancel? = nil) -> CommandResult {
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

        // Read both pipes as the output arrives. Reading them one after the other
        // deadlocks once the other fills its 64 KiB buffer.
        let out = PipeText()
        let err = PipeText()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            out.collect(from: outPipe.fileHandleForReading)
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            err.collect(from: errPipe.fileHandleForReading)
            readers.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        var cancelSeen = false
        while process.isRunning && Date() < deadline {
            if let cancel, cancel.isCancelled { cancelSeen = true; break }
            // No explicit handle: fall back to the action's own cancel scope, so
            // existing callers are unchanged and a perform-scoped action is
            // cancellable end to end.
            scopeLock.lock()
            let ambient = scopedToken
            scopeLock.unlock()
            if let ambient, ambient.isCancelled { cancelSeen = true; break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        var stopped = false
        // Cancelled, not "took too long": the ambient scope stops a run the same
        // way the handle does, and the message must match what happened.
        let cancelled = cancelSeen
        if process.isRunning {
            stopped = true
            process.terminate()
            let grace = Date().addingTimeInterval(2)
            while process.isRunning && Date() < grace {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        // A grandchild can hold the write end open; the answer must not wait for it.
        _ = readers.wait(timeout: .now() + 2)

        var stderr = err.text
        if cancelled {
            let note = "was cancelled"
            stderr = stderr.isEmpty ? note : stderr + "\n" + note
        } else if stopped {
            let ceiling = "\(Int(timeout)) second\(Int(timeout) == 1 ? "" : "s")"
            let note = "took longer than \(ceiling) and was stopped"
            stderr = stderr.isEmpty ? note : stderr + "\n" + note
        }
        return CommandResult(
            status: cancelled ? -3 : (stopped ? -2 : process.terminationStatus),
            stdout: out.text,
            stderr: stderr
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

        // The person has to type their password; that wait is theirs, so its
        // ceiling is generous, but it still has one.
        let result = run(Tool.osascript, ["-e", appleScript], timeout: 300)

        // -128 is AppleScript's "user cancelled".
        if result.status != 0 && (result.stderr.contains("-128") || result.stderr.contains("User canceled")) {
            return CommandResult(status: -128, stdout: "", stderr: "Cancelled — no changes were made.")
        }
        return result
    }
}
