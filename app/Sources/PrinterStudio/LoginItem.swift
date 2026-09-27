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

    /// The executable launchd should start. Captured when the toggle is
    /// switched on, so moving the app afterwards leaves a stale path — the
    /// toggle rewrites it.
    ///
    /// Inside a .app bundle this is simply our own executable. Run from the
    /// standalone report tool there is no app to launch, so it falls back to
    /// the standard install location rather than registering the CLI as a login
    /// item, which is what a naive `Bundle.main` lookup produced.
    private static var executablePath: String {
        if Bundle.main.bundlePath.hasSuffix(".app"), let url = Bundle.main.executableURL {
            return url.resolvingSymlinksInPath().path
        }
        return "/Applications/Printer Studio KH.app/Contents/MacOS/PrinterStudio"
    }

    static func enable() -> CommandResult {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
                <string>--background</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: plistPath).deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Could not enable start at login: \(error.localizedDescription)")
        }

        let uid = getuid()
        _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(uid)/\(label)"])
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
        try? FileManager.default.removeItem(atPath: plistPath)
        return CommandResult(status: 0, stdout: "Printer Studio KH will no longer open at login.", stderr: "")
    }
}
