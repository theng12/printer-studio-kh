import Foundation

/// Registers Printer Studio KH itself to open at login.
///
/// This is separate from the two background services. The share-fix watcher and
/// the AirPrint advertisement are LaunchAgents of their own and already run at
/// login whether or not the app does. This is only about the menu bar icon.
///
/// A LaunchAgent rather than `SMAppService.mainApp`: the app is ad-hoc signed
/// (there is no Developer ID), and a plist in ~/Library/LaunchAgents has no
/// signing requirements and behaves the same on every supported version.
enum LoginItem {

    static let label = "com.theng12.printerstudio.app"

    static var plistPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist").path
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    /// Refresh on launch so moving the app repairs the next login's path.
    private static var appPath: String {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            return Bundle.main.bundleURL.resolvingSymlinksInPath().path
        }
        return "/Applications/Printer Studio KH.app"
    }

    static func enable() -> CommandResult {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-g", "-a", appPath, "--args", "--background"],
            "RunAtLoad": true,
        ]

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: plistPath).deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        } catch {
            return .failure("Could not enable start at login: \(error.localizedDescription)")
        }

        let uid = getuid()
        if Shell.run(Tool.launchctl, ["print", "gui/\(uid)/\(label)"]).ok {
            return CommandResult(status: 0, stdout: "Printer Studio KH will open at login.", stderr: "")
        }
        let bootstrap = Shell.run(Tool.launchctl, ["bootstrap", "gui/\(uid)", plistPath])
        if !bootstrap.ok {
            let legacy = Shell.run(Tool.launchctl, ["load", "-w", plistPath])
            if !legacy.ok {
                return .failure("The login item was written but could not be loaded: \(bootstrap.combined)")
            }
        }
        return CommandResult(status: 0, stdout: "Printer Studio KH will open at login.", stderr: "")
    }

    static func disable() -> CommandResult {
        let uid = getuid()
        _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(uid)/\(label)"])
        do {
            let trash = ShareFix.supportDirectory.appendingPathComponent("_trash/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: plistPath) {
                try FileManager.default.moveItem(atPath: plistPath,
                    toPath: trash.appendingPathComponent("\(label).plist").path)
            }
        } catch {
            return .failure("Could not turn off start at login: \(error.localizedDescription)")
        }
        return CommandResult(status: 0, stdout: "Printer Studio KH will no longer open at login.", stderr: "")
    }
}
