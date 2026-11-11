import Foundation

/// A root-owned, fixed-purpose launchd job; no saved administrator password.
/// It runs at boot and every 15 seconds, including after a USB replug.
///
/// The job runs `Printer Studio KH USB Helper.app`, so Activity Monitor and
/// Login Items show the app instead of `/bin/bash`. Upgrading an older install
/// needs this one administrator prompt, so it happens the next time automatic
/// USB release is turned on.
enum USBPrinterService {
    static let label = "com.theng12.printerstudio.usb"
    static let directory = "/Library/Application Support/PrinterStudio"
    static let helperBundleName = "Printer Studio KH USB Helper"
    static let helperIdentifier = "com.theng12.printerstudio.usbhelper"
    static let helperAppPath = directory + "/\(helperBundleName).app"
    static let helperExecutablePath = helperAppPath + "/Contents/MacOS/\(helperBundleName)"
    /// The shell worker used before 1.0.15. Kept so an upgrade can retire it.
    static let legacyScriptPath = directory + "/keep-usb-printer-ready.sh"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
            && FileManager.default.fileExists(atPath: helperExecutablePath)
            && installedPlistUsesHelper
    }

    private static var installedPlistUsesHelper: Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { return false }
        return arguments == [helperExecutablePath, "usb"]
    }

    static var isLoaded: Bool {
        Shell.run(Tool.launchctl, ["print", "system/\(label)"]).ok
    }

    static var installScript: String? {
        guard let source = ShareFix.bundledHelper(named: helperBundleName) else { return nil }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [helperExecutablePath, "usb"],
            "AssociatedBundleIdentifiers": [helperIdentifier],
            "StartInterval": 15,
            "StandardOutPath": "/var/log/printer-studio-usb.log",
            "StandardErrorPath": "/var/log/printer-studio-usb.err.log",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        else { return nil }
        // Only bundled bytes enter privileged files, never a user-writable path.
        return """
        set -e
        for path in '\(directory)' '\(helperAppPath)' '\(helperExecutablePath)' '\(legacyScriptPath)' '\(plistPath)'; do
            if [ -L "$path" ]; then
                echo "Refusing a symbolic link at $path" >&2
                exit 1
            fi
        done
        /bin/mkdir -p '\(directory)'
        /usr/sbin/chown root:wheel '\(directory)'
        /bin/chmod 755 '\(directory)'
        backup='\(directory)/_trash/'$(/bin/date +%Y%m%d-%H%M%S)-$$
        /bin/mkdir -p "$backup"
        for path in '\(helperAppPath)' '\(legacyScriptPath)' '\(plistPath)'; do
            if [ -e "$path" ]; then /bin/mv "$path" "$backup/"; fi
        done
        /bin/cp -R '\(source)' '\(helperAppPath)'
        /usr/bin/xattr -cr '\(helperAppPath)' 2>/dev/null || true
        /usr/sbin/chown -R root:wheel '\(helperAppPath)'
        /bin/chmod 755 '\(helperExecutablePath)'
        printf '%s' '\(data.base64EncodedString())' | /usr/bin/base64 -D > '\(plistPath)'
        /usr/sbin/chown root:wheel '\(plistPath)'
        /bin/chmod 644 '\(plistPath)'
        /usr/bin/plutil -lint '\(plistPath)'
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        /bin/launchctl bootstrap system '\(plistPath)'
        /bin/launchctl print system/\(label) >/dev/null
        '\(helperExecutablePath)' usb
        echo 'Automatic USB printer release is on, including after a restart.'
        """
    }

    static func enable() -> CommandResult {
        guard let script = installScript else {
            return .failure("The automatic USB printer helper is missing from this build.")
        }
        return Shell.runAsAdministrator(script,
            prompt: "Printer Studio KH needs permission once to keep your USB printer ready after restarts. No password is saved.")
    }

    static func disable() -> CommandResult {
        Shell.runAsAdministrator("""
        set -e
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        if [ -f '\(plistPath)' ]; then
            /bin/mkdir -p '\(directory)/_trash'
            /bin/mv '\(plistPath)' '\(directory)/_trash/\(label).$(/bin/date +%s).plist'
        fi
        echo 'Automatic USB printer release is off.'
        """, prompt: "Printer Studio KH needs permission to turn off automatic USB printer release.")
    }
}
