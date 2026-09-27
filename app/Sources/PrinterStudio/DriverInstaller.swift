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
        return Shell.runAsAdministrator(
            installScript(deviceURI: deviceURI, queueName: queueName, filter: filter, ppd: ppd),
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

        # macOS's IPP-over-USB daemon (ippusbd) claims this printer the moment it
        # appears, because the device advertises an IPP-USB interface. That leaves
        # CUPS's usb backend unable to open it, and the queue reports
        # "The printer is offline" while jobs sit there and never print.
        #
        # Releasing the device is what makes the queue work at all. It is the
        # macOS equivalent of the documented Linux fix, purging ipp-usb.
        # ippusbd is launchd-managed, so it returns after a reboot or if the
        # printer is unplugged and replugged; re-run setup if that happens.
        /usr/bin/killall ippusbd 2>/dev/null || true

        # Share it, and keep the queue open to the LAN from the start.
        /usr/sbin/cupsctl --share_printers=1 --remote_any=1
        /usr/sbin/lpadmin -p '\(queueName)' -u allow:all

        echo "Printer Studio KH: installed '\(queueName)' on \(deviceURI)"
        """
    }

    /// Releases the printer from Apple's IPP-over-USB daemon.
    ///
    /// Needed again after a reboot or a replug: `ippusbd` is launchd-managed,
    /// re-claims the device, and the queue then sits at "The printer is
    /// offline" for ever without logging anything.
    static func releasePrinter() -> CommandResult {
        Shell.runAsAdministrator(
            """
            /usr/bin/killall ippusbd 2>/dev/null || true
            /bin/sleep 1
            if /usr/bin/pgrep -q ippusbd; then
                echo "ippusbd is still running — the printer may stay offline."
            else
                echo "Printer released from the IPP-over-USB service."
            fi
            """,
            prompt: "Printer Studio KH needs to release the printer from macOS's IPP-over-USB service."
        )
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
