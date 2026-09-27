import Foundation

/// Thin, typed wrapper over the CUPS command-line tools.
///
/// Everything here is read-only unless the function name says otherwise, and
/// every call is safe to make from a background thread.
enum CUPS {

    // MARK: - Discovery

    /// Fast listing: `lpstat -p` for names/state plus `lpstat -v` for URIs.
    /// Deliberately does NOT call ipptool, so it can be polled cheaply.
    static func listPrinters() -> [Printer] {
        var found: [String: Printer] = [:]

        let state = Shell.run(Tool.lpstat, ["-p"])
        for raw in state.stdout.split(separator: "\n") {
            let line = String(raw)
            guard line.hasPrefix("printer ") else { continue }
            let body = String(line.dropFirst("printer ".count))
            guard let space = body.firstIndex(of: " ") else { continue }

            let name = String(body[body.startIndex..<space])
            let tail = String(body[body.index(after: space)...])

            var printer = Printer(name: name)
            if tail.hasPrefix("is ") {
                let after = String(tail.dropFirst(3))
                if let dot = after.firstIndex(of: ".") {
                    printer.state = String(after[after.startIndex..<dot])
                }
            } else if tail.hasPrefix("now printing") {
                printer.state = "printing"
            } else if tail.hasPrefix("disabled") {
                printer.state = "stopped"
            } else if let dot = tail.firstIndex(of: ".") {
                printer.state = String(tail[tail.startIndex..<dot])
            }
            if tail.contains("disabled") { printer.enabled = false }
            found[name] = printer
        }

        let devices = Shell.run(Tool.lpstat, ["-v"])
        for raw in devices.stdout.split(separator: "\n") {
            let line = String(raw)
            guard line.hasPrefix("device for ") else { continue }
            let body = String(line.dropFirst("device for ".count))
            guard let range = body.range(of: ": ") else { continue }
            let name = String(body[body.startIndex..<range.lowerBound])
            let uri = String(body[range.upperBound...])
            if var printer = found[name] {
                printer.deviceURI = uri
                found[name] = printer
            }
        }

        return found.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Full IPP attributes for one queue.
    static func attributes(of name: String) -> [String: String] {
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        ) ?? name

        let result = Shell.run(Tool.ipptool, [
            "-tv", "ipp://localhost/printers/\(encoded)",
            "get-printer-attributes.test",
        ])

        var attributes: [String: String] = [:]
        for raw in result.stdout.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let equals = line.range(of: " = ") else { continue }
            let left = String(line[line.startIndex..<equals.lowerBound])
            let value = String(line[equals.upperBound...])
            guard let paren = left.range(of: " (") else { continue }
            attributes[String(left[left.startIndex..<paren.lowerBound])] = value
        }
        return attributes
    }

    /// Listing plus the IPP attributes the Sharing screen needs.
    /// This is the slow path (one ipptool call per queue), so call it off
    /// the main thread and only when the user is looking at that screen.
    static func detailedPrinters() -> [Printer] {
        listPrinters().map { printer in
            var enriched = printer
            let attributes = attributes(of: printer.name)

            if let shared = attributes["printer-is-shared"] {
                enriched.isShared = (shared == "true")
            }
            enriched.hasUserACL = attributes.keys.contains {
                $0.hasPrefix("requesting-user-name-allowed")
            }
            if let model = attributes["printer-make-and-model"], !model.isEmpty {
                enriched.makeAndModel = model
            }
            if let state = attributes["printer-state"] {
                enriched.state = state
            }
            if let accepting = attributes["printer-accepting-jobs"] {
                enriched.accepting = (accepting == "true")
            }
            return enriched
        }
    }

    // MARK: - Global sharing state

    /// Whether the Mac is sharing its printers to the LAN.
    static func isSharingEnabled() -> Bool {
        let result = Shell.run(Tool.cupsctl)
        return result.stdout.contains("_share_printers=1")
    }

    /// Turns Printer Sharing on or off. Needs administrator rights.
    static func setSharingEnabled(_ enabled: Bool) -> CommandResult {
        let script = """
        \(Tool.cupsctl) --share_printers=\(enabled ? 1 : 0) --remote_any=\(enabled ? 1 : 0)
        """
        return Shell.runAsAdministrator(
            script,
            prompt: "Printer Studio KH needs to \(enabled ? "turn on" : "turn off") Printer Sharing."
        )
    }

    // MARK: - Per-queue actions

    /// The core of the "held for authentication" fix: open the queue to all
    /// users at the CUPS layer without disabling sharing.
    static func allowAllUsers(_ name: String) -> CommandResult {
        Shell.run(Tool.lpadmin, ["-p", name, "-u", "allow:all"])
    }

    static func restrictToUserACL(_ name: String) -> CommandResult {
        Shell.run(Tool.lpadmin, ["-p", name, "-u", "allow:@_lpadmin"])
    }

    static func setShared(_ name: String, _ shared: Bool) -> CommandResult {
        Shell.run(Tool.lpadmin, ["-p", name, "-o", "printer-is-shared=\(shared)"])
    }

    static func setEnabled(_ name: String, _ enabled: Bool) -> CommandResult {
        enabled
            ? Shell.run(Tool.lpadmin, ["-p", name, "-E"])
            : Shell.run(Tool.lpadmin, ["-p", name, "-d"])
    }

    /// Sends a real one-page test job to the queue.
    static func printTestPage(_ name: String) -> CommandResult {
        let sample = "/usr/share/cups/ipptool/document-letter.pdf"
        if FileManager.default.fileExists(atPath: sample) {
            return Shell.run(Tool.lp, ["-d", name, sample])
        }
        // Fall back to a plain-text page.
        let text = """
        Printer Studio KH test page
        Queue: \(name)
        Sent: \(Date())
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("printer-studio-test.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return Shell.run(Tool.lp, ["-d", name, url.path])
    }

    // MARK: - Jobs

    /// Jobs that have not finished — including ones parked with
    /// "held for authentication".
    static func unfinishedJobs() -> [String] {
        let result = Shell.run(Tool.lpstat, ["-W", "not-completed"])
        return result.stdout
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func cancelAllJobs(on name: String) -> CommandResult {
        Shell.run(Tool.lprm, ["-a", "-P", name])
    }

    static func cancelJob(_ id: String) -> CommandResult {
        Shell.run(Tool.lprm, [id])
    }
}
