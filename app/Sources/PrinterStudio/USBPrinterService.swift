import Foundation

/// A root-owned, fixed-purpose launchd job; no saved administrator password.
/// It runs at boot and every 15 seconds, including after a USB replug.
enum USBPrinterService {
    static let label = "com.theng12.printerstudio.usb"
    static let directory = "/Library/Application Support/PrinterStudio"
    static let scriptPath = directory + "/keep-usb-printer-ready.sh"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
            && FileManager.default.fileExists(atPath: scriptPath)
    }

    static var isLoaded: Bool {
        Shell.run(Tool.launchctl, ["print", "system/\(label)"]).ok
    }

    static var installScript: String? {
        let source: URL
        if let bundled = Bundle.main.url(forResource: "keep-usb-printer-ready", withExtension: "sh") {
            source = bundled
        } else {
            source = URL(fileURLWithPath: CommandLine.arguments[0])
                .resolvingSymlinksInPath().deletingLastPathComponent()
                .appendingPathComponent("../app/Resources/keep-usb-printer-ready.sh")
        }
        guard let payload = try? Data(contentsOf: source) else { return nil }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/bash", scriptPath],
            "RunAtLoad": true,
            "StartInterval": 15,
            "StandardOutPath": "/var/log/printer-studio-usb.log",
            "StandardErrorPath": "/var/log/printer-studio-usb.err.log",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        else { return nil }
        // Only bundled bytes enter privileged files, never a user-writable script path.
        return """
        set -e
        for path in '\(directory)' '\(scriptPath)' '\(plistPath)'; do
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
        for path in '\(scriptPath)' '\(plistPath)'; do
            if [ -e "$path" ]; then /bin/cp -p "$path" "$backup/"; fi
        done
        printf '%s' '\(payload.base64EncodedString())' | /usr/bin/base64 -D > '\(scriptPath)'
        /usr/sbin/chown root:wheel '\(scriptPath)'
        /bin/chmod 755 '\(scriptPath)'
        printf '%s' '\(data.base64EncodedString())' | /usr/bin/base64 -D > '\(plistPath)'
        /usr/sbin/chown root:wheel '\(plistPath)'
        /bin/chmod 644 '\(plistPath)'
        /usr/bin/plutil -lint '\(plistPath)'
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        /bin/launchctl bootstrap system '\(plistPath)'
        /bin/launchctl print system/\(label) >/dev/null
        /bin/bash '\(scriptPath)'
        echo 'Automatic USB printer release is on, including after a restart.'
        """
    }

    static func enable() -> CommandResult {
        guard let script = installScript else {
            return .failure("The automatic USB printer service is missing from this build.")
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
