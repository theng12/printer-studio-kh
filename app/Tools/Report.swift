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
        if arguments.contains("--list-sticker-sizes") {
            for size in StickerSizeStore.load() {
                print("\(size.enabled ? "[x]" : "[ ]") \(size.label)")
                print("      ppd key: \(size.key)")
            }
            exit(0)
        }
        if let at = arguments.firstIndex(of: "--preview-sticker-ppd"), at + 1 < arguments.count {
            let path = arguments[at + 1]
            guard let ppd = try? String(contentsOfFile: path, encoding: .utf8) else {
                print("cannot read \(path)")
                exit(1)
            }
            // Written with FileHandle, not print(): print() appends a newline,
            // which made a re-apply look non-idempotent when it was not.
            let transformed = PageSizeInstaller.transform(
                ppd: ppd, adding: StickerSizeStore.load())
            FileHandle.standardOutput.write(Data(transformed.utf8))
            exit(0)
        }
        if arguments.contains("--label-queues") {
            let all = PageSizeInstaller.queues()
            if all.isEmpty { print("no queues") }
            for entry in all {
                let maxWidth = PageSizeInstaller.maxWidthMM(queue: entry.queue)
                    .map { String(format: "%.0f mm", $0) } ?? "unknown"
                let sizes = PageSizeInstaller.currentSizes(queue: entry.queue)
                print("\(entry.isLabel ? "LABEL" : "other")  \(entry.queue)")
                print("       offers \(sizes.count): \(sizes.joined(separator: " "))")
                print("       max width: \(maxWidth)")
            }
            exit(0)
        }
        if arguments.contains("--apply-sticker-sizes") {
            let targets = PageSizeInstaller.queues().filter { $0.isLabel }.map { $0.queue }
            let result = PageSizeInstaller.apply(sizes: StickerSizeStore.load(), to: targets)
            print(result.combined.isEmpty ? "Applied." : result.combined)
            exit(result.ok ? 0 : 1)
        }
        if arguments.contains("--print-usb-service-install-script") {
            guard let script = USBPrinterService.installScript else { exit(1) }
            print(script)
            exit(0)
        }
        if arguments.contains("--install-usb-service") {
            let result = USBPrinterService.enable()
            print(result.combined)
            exit(result.ok ? 0 : 1)
        }
        if arguments.contains("--enable-login-item") {
            let result = LoginItem.enable()
            print(result.combined.isEmpty ? "Login item enabled." : result.combined)
            exit(result.ok ? 0 : 1)
        }
        if arguments.contains("--disable-login-item") {
            let result = LoginItem.disable()
            print(result.combined.isEmpty ? "Login item disabled." : result.combined)
            exit(result.ok ? 0 : 1)
        }
        if arguments.contains("--install-airprint") {
            let result = DriverInstaller.installAirPrintBridge()
            print(result.combined.isEmpty ? "AirPrint advertisement installed." : result.combined)
            exit(result.ok ? 0 : 1)
        }
        if arguments.contains("--remove-airprint") {
            let result = DriverInstaller.removeAirPrintBridge()
            print(result.combined.isEmpty ? "AirPrint advertisement removed." : result.combined)
            exit(result.ok ? 0 : 1)
        }
        if arguments.contains("--print-install-script") {
            // Prints the exact shell the installer would run as administrator,
            // so it can be syntax-checked without executing anything.
            print(DriverInstaller.installScript(
                deviceURI: DriverInstaller.usbDeviceURI() ?? "usb://HP/Laser%20107a",
                filter: DriverInstaller.bundledFilter ?? "/path/to/rastertoqpdl",
                ppd: DriverInstaller.bundledPPD ?? "/path/to/laser10x.ppd"
            ))
            exit(0)
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

        let interfaces = Driver.usbInterfaces()
        section("USB interfaces")
        print("(\(interfaces.count) interface descriptor\(interfaces.count == 1 ? "" : "s") readable)")
        let notable = interfaces.filter { $0.note != nil }
        if notable.isEmpty {
            print("(none are printer-class)")
        } else {
            for entry in notable {
                print("• \(entry.productName)  [\(entry.summary)]")
                if let note = entry.note { print("      \(note)") }
            }
        }

        if let laser = Driver.connectedLaser107a {
            let own = interfaces.filter { $0.productName == laser.name }
            print("")
            print("Verdict for \(laser.name):")
            if own.isEmpty {
                print("    interface descriptors could not be read")
            } else if own.contains(where: { $0.isIPPOverUSB }) {
                print("    exposes IPP-over-USB (protocol 4). If that is the setting the")
                print("    firmware is currently on, it will discard a raw print stream")
                print("    without reporting anything. This is the known risk for this family.")
            } else if own.contains(where: { $0.isClassicPrinter }) {
                print("    offers a classic printer interface (protocol 1 or 2) — the mode")
                print("    a CUPS backend needs.")
            } else {
                print("    printer-class, but no classic or IPP-over-USB interface seen.")
            }
        }

        section("HP Laser 107a driver")
        print("Automatic USB   installed=\(USBPrinterService.isInstalled) loaded=\(USBPrinterService.isLoaded)")
        print("Connected       \(Driver.connectedLaser107a != nil ? "yes" : "no")")
        print("Held by ippusbd \(Driver.ippusbdHoldingPrinter() ? "YES — queue will report offline and nothing will print" : "no")")
        print("CUPS filter     \(Driver.installedFilter ?? "NOT INSTALLED")")
        print("PPD             \(Driver.installedPPD ?? "NOT INSTALLED")")
        print("Ready           \(Driver.isReady ? "yes" : "no")")
        print("Would install   \(DriverInstaller.usbDeviceURI() ?? "(no USB printer found)")")
        print("Bundled filter  \(DriverInstaller.bundledFilter ?? "MISSING FROM BUILD")")
        print("Bundled PPD     \(DriverInstaller.bundledPPD ?? "MISSING FROM BUILD")")

        section("AirPrint advertisement for iOS")
        print("Installed       \(DriverInstaller.isAirPrintInstalled ? "yes" : "no")")
        print("Open at login   \(LoginItem.isEnabled ? "yes" : "no")")
        let advertisers = Shell.run(Tool.pgrep, ["-fl", "dns-sd -R"])
        let advertised = advertisers.stdout
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard let range = line.range(of: "dns-sd -R ") else { return nil }
                let rest = line[range.upperBound...]
                // The service name runs up to the service type; without this it
                // truncates at the first space and prints just "HP".
                if let type = rest.range(of: " _ipp._tcp") {
                    return String(rest[rest.startIndex..<type.lowerBound])
                }
                return String(rest.prefix(50))
            }
        if advertised.isEmpty {
            print("Advertising     (nothing)")
        } else {
            for name in advertised { print("Advertising     \(name)") }
        }

        // The USB backend's own discovery output. This is the first thing to
        // look at when the printer is attached but nothing prints: it says
        // whether CUPS can see the device at all, and it is the layer that
        // this printer family is reported to be fussy about.
        section("CUPS USB backend discovery")
        let usbBackend = "/usr/libexec/cups/backend/usb"
        if FileManager.default.isExecutableFile(atPath: usbBackend) {
            let discovery = Shell.run(usbBackend, [])
            let lines = discovery.stdout
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if lines.isEmpty {
                print("(the backend reports no USB printers)")
            } else {
                for line in lines { print(line) }
            }
        } else {
            print("(no USB backend at \(usbBackend))")
        }

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
