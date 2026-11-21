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

    /// macOS is holding the item until the person allows it. Never reported as on.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// What to tell the person for each registration state. One source of truth,
    /// so no caller can replace the answer with a success sentence.
    static func message(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "Printer Studio KH will open at login."
        case .requiresApproval:
            return "Printer Studio KH cannot open at login until you allow it in System Settings > General > Login Items."
        case .notRegistered: return "Printer Studio KH is not set to open at login."
        case .notFound:
            return "macOS cannot find Printer Studio KH's login item. Move the app to Applications and turn it on again."
        @unknown default: return "macOS did not confirm that Printer Studio KH will open at login."
        }
    }

    /// What a launch should do about the registration. A separate, pure decision
    /// so the no-op case is proved by the absence of a call, not by silence.
    enum RegistrationAction: Equatable {
        case none
        case register
        case reRegister
    }

    static let markerKey = "loginItemRegisteredBuild"
    static var storedBuild: String? { UserDefaults.standard.string(forKey: markerKey) }
    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// `register` covers the first run and any state that is not enabled.
    /// `reRegister` is the one-time refresh after a version or identity change;
    /// with the same marker it is `none` — no unregister, no register, no write.
    static func registrationAction(storedBuild: String?, currentBuild: String,
                                   isEnabled: Bool, isConfigured: Bool) -> RegistrationAction {
        guard isConfigured else { return .register }
        guard isEnabled else { return .register }
        return storedBuild == currentBuild ? .none : .reRegister
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
        let result = result(for: service)
        // The marker and the registration are written together; a state that is
        // not enabled never records one, so the next launch tries again.
        if service.status == .enabled { UserDefaults.standard.set(currentBuild, forKey: markerKey) }
        return result
    }

    /// Once per build: drop and re-add the registration so it carries the current
    /// signing identity. A registration made before the certificate changed is
    /// otherwise never refreshed — `enable()` registers only when nothing is there.
    /// Nil means there is nothing to do.
    static func refreshRegistration(build: String) -> CommandResult? {
        let service = SMAppService.mainApp
        let action = registrationAction(storedBuild: storedBuild, currentBuild: build,
                                        isEnabled: service.status == .enabled, isConfigured: true)
        guard action == .reRegister else { return nil }
        do {
            try service.unregister()
            try service.register()
        } catch {
            return .failure("Printer Studio KH could not refresh its login item: \(error.localizedDescription)")
        }
        if service.status == .enabled { UserDefaults.standard.set(build, forKey: markerKey) }
        return result(for: service)
    }

    /// Not enabled is a failure here: the person asked for it and macOS is not
    /// running it yet, so the caller must not report success.
    private static func result(for service: SMAppService) -> CommandResult {
        service.status == .enabled
            ? CommandResult(status: 0, stdout: message(for: .enabled), stderr: "")
            : .failure(message(for: service.status))
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
