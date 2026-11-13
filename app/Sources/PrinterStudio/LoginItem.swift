import Foundation
import ServiceManagement

/// Registers Printer Studio KH itself to open at login through the system's own
/// Login Items list (`SMAppService.mainApp`).
///
/// This is separate from the background helper job, which runs at login on its
/// own. Older builds used a LaunchAgent running `open -g`; it is booted out and
/// retired on the next enable so Login Items ends with one app row, not two.
enum LoginItem {

    /// The LaunchAgent older builds wrote.
    static let label = "com.theng12.printerstudio.app"

    private static var legacyAgentPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist", isDirectory: false)
    }

    /// The app the person sees in System Settings. A leftover legacy agent
    /// still starts the app at login, so it counts as enabled until retired.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
            || FileManager.default.fileExists(atPath: legacyAgentPath.path)
    }

    static func enable() -> CommandResult {
        let service = SMAppService.mainApp
        if service.status == .notRegistered || service.status == .notFound {
            do {
                try service.register()
            } catch {
                return .failure("Could not enable start at login: \(error.localizedDescription)")
            }
        }
        guard retireLegacyAgent() else {
            return .failure("Printer Studio KH will open at login, but the old login item could not be retired. Remove it from Login Items.")
        }
        if service.status == .requiresApproval {
            return CommandResult(
                status: 0,
                stdout: "Printer Studio KH will open at login once you allow it in System Settings > General > Login Items.",
                stderr: "")
        }
        return CommandResult(status: 0, stdout: "Printer Studio KH will open at login.", stderr: "")
    }

    static func disable() -> CommandResult {
        let service = SMAppService.mainApp
        if service.status == .enabled || service.status == .requiresApproval {
            do {
                try service.unregister()
            } catch {
                return .failure("Could not turn off start at login: \(error.localizedDescription)")
            }
        }
        guard retireLegacyAgent() else {
            return .failure("Could not turn off start at login: the old login item could not be moved to _trash.")
        }
        return CommandResult(status: 0, stdout: "Printer Studio KH will no longer open at login.", stderr: "")
    }

    /// Boots out and moves the old `open -g` agent to the app's support
    /// `_trash`. Never deletes it.
    private static func retireLegacyAgent() -> Bool {
        guard FileManager.default.fileExists(atPath: legacyAgentPath.path) else { return true }
        _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(getuid())/\(label)"])
        return ShareFix.moveToTrash(legacyAgentPath.path) != nil
    }
}
