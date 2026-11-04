import Foundation

/// Installs the splix driver and creates the print queue for the HP Laser 107a.
///
/// Everything here needs administrator rights, so the work is handed to
/// `Shell.runAsAdministrator`, which triggers macOS's own password dialog.
///
/// Why splix rather than the original hand-written encoder: this engine
/// silently discards a page whose band width is not exactly one of a fixed
/// set of values. splix carries the table observed from Samsung's own driver
/// and gates it on the PPD attribute `*QPDL SpecialBandWidth`. Without that
/// gate the stream is accepted, no error is reported, and no paper moves.
enum DriverInstaller {

    /// The queue name created on this Mac.
    static let queueName = "HPLaser107a"

    static let filterDestination = "/usr/libexec/cups/filter/rastertoqpdl"
    static let ppdDestination = "/Library/Printers/PPDs/Contents/Resources/laser10x.ppd"

    // MARK: - Bundled payload

    static var bundledFilter: String? { locate("rastertoqpdl", in: "bin") }
    static var bundledPPD: String? { locate("laser10x.ppd", in: "ppd") }

    static var hasPayload: Bool { bundledFilter != nil && bundledPPD != nil }

    /// Finds a file shipped inside the app bundle, falling back to the
    /// development checkout so the CLI report tool works too.
    private static func locate(_ filename: String, in subdirectory: String) -> String? {
        let fileManager = FileManager.default
        var directories: [URL] = []

        if let resources = Bundle.main.resourceURL {
            directories.append(resources.appendingPathComponent("splix/\(subdirectory)"))
        }

        // Standalone tools are built into dist/, beside the checkout.
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        directories.append(executableDirectory.appendingPathComponent("../vendor/splix/\(subdirectory)"))
        directories.append(executableDirectory.appendingPathComponent("vendor/splix/\(subdirectory)"))

        for directory in directories {
            let candidate = directory.appendingPathComponent(filename).standardizedFileURL.path
            if fileManager.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    // MARK: - USB discovery

    /// Asks CUPS which USB printers it can see, preferring our own device.
    static func usbDeviceURI() -> String? {
        let result = Shell.run(Tool.lpinfo, ["-v"])
        var fallback: String?

        for raw in result.stdout.split(separator: "\n") {
            let line = String(raw)
            guard let range = line.range(of: "usb://") else { continue }
            let uri = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
            let lower = uri.lowercased()

            if lower.contains("107") || lower.contains("m2026") || lower.contains("m2020") {
                return uri
            }
            if fallback == nil, lower.contains("laser") || lower.contains("hp/") || lower.contains("samsung") {
                fallback = uri
            }
        }
        return fallback
    }

    // MARK: - Install / uninstall

    /// Installs the filter and PPD, creates the queue, and turns on sharing.
    static func install(deviceURI: String, queueName: String = DriverInstaller.queueName) -> CommandResult {
        guard let filter = bundledFilter, let ppd = bundledPPD else {
            return .failure("The bundled splix driver is missing from this build.")
        }
        guard let service = USBPrinterService.installScript else {
            return .failure("The automatic USB printer service is missing from this build.")
        }
        return Shell.runAsAdministrator(
            installScript(deviceURI: deviceURI, queueName: queueName, filter: filter, ppd: ppd) + "\n" + service,
            prompt: "Printer Studio KH needs to install the printer driver for the HP Laser 107a."
        )
    }

    /// The exact shell the installer runs, returned as a value so it can be
    /// inspected and syntax-checked without executing anything privileged.
    /// `printer-studio-report --print-install-script` prints it.
    static func installScript(
        deviceURI: String,
        queueName: String = DriverInstaller.queueName,
        filter: String,
        ppd: String
    ) -> String {
        """
        set -e

        /bin/mkdir -p /usr/libexec/cups/filter
        /bin/mkdir -p /Library/Printers/PPDs/Contents/Resources

        # The PPD refers to the filter by bare name, so it must live in CUPS's
        # own filter directory. /usr/libexec/cups is exempt from SIP.
        /bin/cp -f '\(filter)' '\(filterDestination)'
        /usr/sbin/chown root:wheel '\(filterDestination)'
        # CUPS refuses to run a filter that is group- or world-writable; 0555
        # is what it documents and expects.
        /bin/chmod 555 '\(filterDestination)'
        # Clear every extended attribute, and above all com.apple.quarantine.
        # If this app arrived by AirDrop, Telegram or a download, that flag is
        # on the bundle, and the copied driver inherits it. A quarantined
        # filter makes Gatekeeper stall the job rather than run it, which
        # looks exactly like "printing silently does nothing".
        /usr/bin/xattr -c '\(filterDestination)' 2>/dev/null || true
        # Ad-hoc signing is mandatory on Apple Silicon. An unsigned binary is
        # killed by AMFI the instant cupsd execs it, and CUPS reports that only
        # as "Filter failed". Notarization is not needed for a local copy.
        /usr/bin/codesign --force --sign - '\(filterDestination)' 2>/dev/null || true
        /usr/bin/codesign --verify '\(filterDestination)' 2>/dev/null || echo "warning: filter signature could not be verified"

        /bin/cp -f '\(ppd)' '\(ppdDestination)'
        /bin/chmod 644 '\(ppdDestination)'
        /usr/sbin/chown root:wheel '\(ppdDestination)'
        /usr/bin/xattr -c '\(ppdDestination)' 2>/dev/null || true

        # Remove any previous queue, then create the real one.
        /usr/sbin/lpadmin -x '\(queueName)' 2>/dev/null || true
        /usr/sbin/lpadmin \\
            -p '\(queueName)' \\
            -E \\
            -v '\(deviceURI)' \\
            -P '\(ppdDestination)' \\
            -D 'HP Laser 107a' \\
            -L 'Printer Studio KH' \\
            -o printer-is-shared=true \\
            -o printer-error-policy=retry-job

        # The persistent USB service is installed with the same approval below.

        # Share it, and keep the queue open to the LAN from the start.
        /usr/sbin/cupsctl --share-printers
        /usr/sbin/lpadmin -p '\(queueName)' -u allow:all

        echo "Printer Studio KH: installed '\(queueName)' on \(deviceURI)"
        """
    }

    /// Existing installations migrate with one approval, then run at boot.
    static func releasePrinter() -> CommandResult {
        if USBPrinterService.isInstalled && USBPrinterService.isLoaded {
            return CommandResult(status: 0,
                stdout: "Automatic release is running; the USB printer is checked every 15 seconds.", stderr: "")
        }
        return USBPrinterService.enable()
    }

    // MARK: - AirPrint advertisement for iOS

    static let airPrintLabel = "com.theng12.printerstudio.airprint"

    /// The test suite sets these so it works in a scratch directory and
    /// never loads a launchd job.
    ///
    /// PRINTER_STUDIO_AIRPRINT_TEST=1 turns on test mode.
    /// PRINTER_STUDIO_SUPPORT_DIR says where the scratch files live.
    static var isTestMode: Bool {
        ProcessInfo.processInfo.environment["PRINTER_STUDIO_AIRPRINT_TEST"] == "1"
    }

    /// Installed per-user, not per-machine.
    ///
    /// `dns-sd` needs no privileges to publish a Bonjour service, so this needs
    /// no administrator password and matches how the share-fix watcher is
    /// installed. The trade-off: it starts at login rather than at boot, so a
    /// Mac that reboots to the login screen and stays there advertises nothing
    /// until someone logs in.
    static var airPrintAgentPath: String {
        if isTestMode {
            return airPrintSupportDirectory
                .appendingPathComponent("LaunchAgents/\(airPrintLabel).plist").path
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(airPrintLabel).plist").path
    }

    static var airPrintScriptPath: String {
        airPrintSupportDirectory.appendingPathComponent("airprint-bridge.sh").path
    }

    /// Where the advertisement script and its LaunchAgent live.
    ///
    /// The environment override lets the test suite work in a scratch
    /// directory instead of the user's own installation.
    static var airPrintSupportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["PRINTER_STUDIO_SUPPORT_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return ShareFix.supportDirectory
    }

    /// The launcher script, shipped inside the app bundle, with a fallback to
    /// the checkout so the standalone report tool can install it too.
    static var bundledAirPrintScript: String? {
        if let override = ProcessInfo.processInfo.environment["PRINTER_STUDIO_BUNDLED_SCRIPT"],
           FileManager.default.fileExists(atPath: override) {
            return override
        }
        if let url = Bundle.main.url(forResource: "airprint-bridge", withExtension: "sh") {
            return url.path
        }
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        let candidate = executableDirectory
            .appendingPathComponent("../app/Resources/airprint-bridge.sh")
            .standardizedFileURL.path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    static var isAirPrintInstalled: Bool {
        FileManager.default.fileExists(atPath: airPrintAgentPath)
    }

    /// Where replaced and removed files are kept. Nothing is deleted: a
    /// wrong script is still recoverable, and the old one stays readable next
    /// to the new one.
    private static var trashDirectory: URL {
        airPrintSupportDirectory.appendingPathComponent("_trash", isDirectory: true)
    }

    /// Moves a file into `_trash` under a dated name and returns the new
    /// path. A file that is not there is not an error.
    @discardableResult
    private static func moveToTrash(_ path: String) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = trashDirectory
            .appendingPathComponent("\(name).\(stamp).\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
            try fileManager.moveItem(atPath: path, toPath: destination.path)
            return destination.path
        } catch {
            return nil
        }
    }

    /// Exposes the trash rule to the test suite.
    static func moveToTrashForTesting(_ path: String) -> String? {
        moveToTrash(path)
    }

    /// Copies the bundled script into place, keeping the old one in `_trash`.
    private static func installScriptFile(from source: String) -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: airPrintSupportDirectory,
                                            withIntermediateDirectories: true)
            _ = moveToTrash(airPrintScriptPath)
            try fileManager.copyItem(atPath: source, toPath: airPrintScriptPath)
            try fileManager.setAttributes([.posixPermissions: 0o755],
                                          ofItemAtPath: airPrintScriptPath)
            return true
        } catch {
            return false
        }
    }

    /// Replaces the installed script and restarts the agent.
    private static func reloadAgent() -> CommandResult {
        if isTestMode {
            // No launchd job in the test suite.
            return CommandResult(status: 0, stdout: "AirPrint advertisement started.", stderr: "")
        }
        let uid = getuid()
        _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(uid)/\(airPrintLabel)"])
        let bootstrap = Shell.run(Tool.launchctl, ["bootstrap", "gui/\(uid)", airPrintAgentPath])
        if !bootstrap.ok {
            let legacy = Shell.run(Tool.launchctl, ["load", "-w", airPrintAgentPath])
            if !legacy.ok {
                return .failure(
                    "The advertisement was written but could not be started: \(bootstrap.combined)")
            }
        }
        _ = Shell.run(Tool.launchctl, ["kickstart", "-k", "gui/\(uid)/\(airPrintLabel)"])
        return CommandResult(status: 0, stdout: "AirPrint advertisement started.", stderr: "")
    }

    /// Publishes an AirPrint advertisement for every shared queue.
    ///
    /// macOS Printer Sharing does not publish the `_universal` subtype or a
    /// `URF=` TXT key, and iOS ignores a printer without them — which is why a
    /// Mac-shared printer never appears on an iPhone even though it works from
    /// other Macs. This adds a Bonjour record per shared queue pointing at
    /// the same CUPS queue. Nothing is proxied; jobs take the same path.
    static func installAirPrintBridge() -> CommandResult {
        guard let source = bundledAirPrintScript else {
            return .failure("The AirPrint advertisement script is missing from this build.")
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: URL(fileURLWithPath: airPrintAgentPath).deletingLastPathComponent(),
                withIntermediateDirectories: true)
        } catch {
            return .failure("Could not install the AirPrint advertisement: \(error.localizedDescription)")
        }

        guard installScriptFile(from: source) else {
            return .failure("Could not install the AirPrint advertisement script.")
        }

        do {
            try agentPlist.write(toFile: airPrintAgentPath, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Could not install the AirPrint advertisement: \(error.localizedDescription)")
        }

        let started = reloadAgent()
        guard started.ok else { return started }
        return CommandResult(status: 0, stdout: "AirPrint advertisement installed.", stderr: "")
    }

    /// Updates an installed advertisement script when the app ships a newer
    /// one, so a fix reaches a Mac that already has the advertisement on.
    ///
    /// Does nothing when the advertisement is off, and nothing when the
    /// installed script already matches the bundled one. The LaunchAgent is
    /// left alone: its contents do not change with the script.
    @discardableResult
    static func refreshAirPrintBridgeIfOutdated() -> CommandResult {
        guard isAirPrintInstalled else {
            return CommandResult(status: 0, stdout: "AirPrint advertisement is off.", stderr: "")
        }
        guard let source = bundledAirPrintScript,
              let bundled = try? Data(contentsOf: URL(fileURLWithPath: source)) else {
            return .failure("The AirPrint advertisement script is missing from this build.")
        }
        let installedPath = URL(fileURLWithPath: airPrintScriptPath)
        if let installed = try? Data(contentsOf: installedPath), installed == bundled {
            return CommandResult(status: 0, stdout: "AirPrint advertisement is up to date.", stderr: "")
        }
        guard installScriptFile(from: source) else {
            return .failure("Could not update the AirPrint advertisement script.")
        }
        let started = reloadAgent()
        guard started.ok else { return started }
        return CommandResult(status: 0, stdout: "AirPrint advertisement updated.", stderr: "")
    }

    static func removeAirPrintBridge() -> CommandResult {
        let uid = getuid()
        _ = Shell.run(Tool.launchctl, ["bootout", "gui/\(uid)/\(airPrintLabel)"])

        for path in [airPrintAgentPath, airPrintScriptPath] {
            if FileManager.default.fileExists(atPath: path), moveToTrash(path) == nil {
                return .failure("Could not move the AirPrint files to _trash. The service was stopped; check file permissions and try again.")
            }
        }

        return CommandResult(
            status: 0,
            stdout: "AirPrint advertisement removed. The old files are kept in "
                + trashDirectory.path + ".",
            stderr: "")
    }

    private static var agentPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(airPrintLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(airPrintScriptPath)</string>
                <string>run</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }

    /// Removes the queue, the filter and the PPD.
    static func uninstall(queueName: String = DriverInstaller.queueName) -> CommandResult {
        let script = """
        /usr/sbin/lpadmin -x '\(queueName)' 2>/dev/null || true
        /bin/rm -f '\(filterDestination)'
        /bin/rm -f '\(ppdDestination)'
        echo "Printer Studio KH: removed '\(queueName)' and the splix driver."
        """
        return Shell.runAsAdministrator(
            script,
            prompt: "Printer Studio KH needs to remove the printer driver."
        )
    }
}

