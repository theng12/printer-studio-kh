import Foundation

/// A plain-text diagnostic report, built from the very same service code the
/// app uses. Two purposes:
///
///   * it lets the whole data layer be verified without a GUI, and
///   * it is the thing to run when a print queue misbehaves, since it prints
///     everything the app would show.
@main
struct Report {
    static func main() {
        // Actions, so the service code can be exercised (and recovered) from
        // a shell without the GUI. `printer-studio-report` with no arguments
        // prints the report.
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--fix-sharing") {
            let result = ShareFix.fixNow()
            print(result.combined.isEmpty ? "Shared queues checked." : result.combined)
            exit(result.ok ? 0 : 1)
        }
        if arguments.contains("--install-watcher") {
            let result = ShareFix.installWatcher()
            print(result.combined.isEmpty ? "Watcher installed." : result.combined)
            exit(result.ok ? 0 : 1)
        }
        if arguments.contains("--remove-watcher") {
            let result = ShareFix.uninstallWatcher()
            print(result.combined.isEmpty ? "Watcher removed." : result.combined)
            exit(result.ok ? 0 : 1)
        }

        let line = String(repeating: "─", count: 68)

        print(line)
        print("Printer Studio KH — diagnostic report")
        print(Date().formatted(date: .abbreviated, time: .standard))
        print(line)

        section("System")
        print("macOS           \((Shell.run("/usr/bin/sw_vers", ["-productVersion"]).stdout).trimmingCharacters(in: .whitespacesAndNewlines))")
        print("Architecture    \(Shell.run("/usr/bin/uname", ["-m"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        print("CUPS            \(Shell.run(Tool.cupsConfig, ["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        print("Sharing         \(CUPS.isSharingEnabled() ? "ON" : "off")")

        section("Print queues")
        let printers = CUPS.detailedPrinters()
        if printers.isEmpty {
            print("(no print queues)")
        }
        for printer in printers {
            print("• \(printer.name)")
            print("    state       \(printer.state)\(printer.enabled ? "" : " (paused)")")
            print("    connection  \(printer.friendlyLocation)")
            print("    model       \(printer.makeAndModel.isEmpty ? "—" : printer.makeAndModel)")
            print("    shared      \(printer.isShared ? "yes" : "no")")
            if printer.isShared {
                print("    access      \(printer.hasUserACL ? "LOCKED to specific users  <-- other Macs will see \"Job held for authentication\"" : "open to everyone")")
            }
        }

        let jobs = CUPS.unfinishedJobs()
        section("Unfinished jobs")
        print(jobs.isEmpty ? "(none)" : jobs.joined(separator: "\n"))

        section("USB devices")
        let devices = Driver.usbDevices()
        if devices.isEmpty {
            print("(none detected)")
        }
        for device in devices {
            print("• \(device.name)  [\(device.vendorID):\(device.productID)]\(device.isLaser107a ? "   <-- HP Laser 107a" : "")")
        }

        section("HP Laser 107a driver")
        print("Connected       \(Driver.connectedLaser107a != nil ? "yes" : "no")")
        print("CUPS filter     \(Driver.installedFilter ?? "NOT INSTALLED")")
        print("PPD             \(Driver.installedPPD ?? "NOT INSTALLED")")
        print("Ready           \(Driver.isReady ? "yes" : "no")")

        section("Share-fix watcher")
        print("Installed       \(ShareFix.isWatcherInstalled ? "yes" : "no")")
        print("Loaded          \(ShareFix.isWatcherLoaded ? "yes" : "no")")
        print("Log             \(ShareFix.logFile.path)")
        let log = ShareFix.recentLogLines(limit: 8)
        if log.isEmpty {
            print("(no log entries)")
        } else {
            for entry in log { print("    \(entry)") }
        }

        print(line)
    }

    private static func section(_ title: String) {
        print("")
        print("▸ \(title)")
    }
}
