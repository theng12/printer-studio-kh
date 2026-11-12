import AppKit
import Foundation

/// Takes the app back off this Mac in one step: the launchd jobs, the helper
/// bundles, the login item and the app itself. What the person made — settings,
/// saved sticker sizes, printer names — stays exactly where it is.
enum Removal {

    /// Removes every installed piece and reports what happened, naming the first
    /// thing that would not go rather than claiming success.
    static func everything() -> CommandResult {
        var removed: [String] = []
        var failures: [String] = []

        func attempt(_ what: String, _ work: () -> CommandResult) {
            let result = work()
            if result.ok { removed.append(what) }
            else { failures.append("\(what) — \(result.combined)") }
        }

        attempt("the AirPrint advertisement") { DriverInstaller.removeAirPrintBridge() }
        attempt("the shared-queue watcher") { ShareFix.uninstallWatcher() }
        attempt("the USB release helper") { USBPrinterService.disable() }
        attempt("open at login") { LoginItem.disable() }

        retireHelpers(into: &removed, failures: &failures)
        retireAppBundle(into: &removed, failures: &failures)

        if let first = failures.first {
            return .failure("Could not remove \(first)")
        }
        return CommandResult(status: 0, stdout: "Removed \(removed.joined(separator: ", ")).", stderr: "")
    }

    /// Helper bundles are moved, never deleted, so a mistake can be undone by
    /// dragging them back.
    private static func retireHelpers(into removed: inout [String], failures: inout [String]) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let trash = ShareFix.supportDirectory.appendingPathComponent("_trash/removed-\(stamp)", isDirectory: true)
        let bundles = [
            ShareFix.helperApp,
            ShareFix.supportDirectory.appendingPathComponent("\(ShareFix.usbHelperBundleName).app", isDirectory: true),
        ]
        do {
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        } catch {
            failures.append("the helper bundles — \(error.localizedDescription)")
            return
        }
        for bundle in bundles where FileManager.default.fileExists(atPath: bundle.path) {
            do {
                try FileManager.default.moveItem(at: bundle, to: trash.appendingPathComponent(bundle.lastPathComponent))
                removed.append(bundle.lastPathComponent)
            } catch {
                failures.append("\(bundle.lastPathComponent) — \(error.localizedDescription)")
            }
        }
    }

    /// Moves the installed app itself aside, and only when it really is the
    /// installed copy: a build running out of dist must not remove itself.
    private static func retireAppBundle(into removed: inout [String], failures: inout [String]) {
        let bundle = Bundle.main.bundleURL
        guard bundle.path.hasPrefix("/Applications/") else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let trash = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/_trash/\(stamp.prefix(10)) printer-studio-kh-uninstalled", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: bundle, to: trash.appendingPathComponent(bundle.lastPathComponent))
            removed.append(bundle.lastPathComponent)
        } catch {
            failures.append("the app itself — \(error.localizedDescription)")
        }
    }

    /// A second copy of the app — a build beside the installed one, or two
    /// installs — must say so plainly instead of both running and fighting over
    /// the same launchd jobs.
    static func anotherCopyIsRunning() -> URL? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let mine = Bundle.main.bundleURL.resolvingSymlinksInPath()
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) {
            guard let url = app.bundleURL?.resolvingSymlinksInPath(), url != mine else { continue }
            return url
        }
        return nil
    }
}
