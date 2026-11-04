import Foundation

/// Builds a safely redacted plain-text error report for troubleshooting.
///
/// Designed to run off the main thread. All text is passed through the
/// sanitizer to ensure credentials, tokens, secrets, passwords, and hardware
/// serial numbers are never exposed.
enum DiagnosticReport {

    // MARK: - Sanitizer

    /// Redacts credentials, tokens, secrets, passwords, passphrases, serial numbers, and URL userinfo.
    /// Potentially sensitive entire lines and private key blocks are suppressed for safety.
    static func sanitize(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var sanitizedLines: [String] = []
        var inPrivateKeyBlock = false

        for line in lines {
            if inPrivateKeyBlock {
                if line.range(of: "-----END [A-Z0-9 ]*PRIVATE KEY-----", options: .regularExpression) != nil {
                    inPrivateKeyBlock = false
                    sanitizedLines.append("[REDACTED SENSITIVE LINE]")
                }
                continue
            }

            if line.range(of: "-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----", options: .regularExpression) != nil {
                inPrivateKeyBlock = true
                sanitizedLines.append("[REDACTED SENSITIVE LINE]")
                continue
            }

            if let sanitized = sanitizeLine(line) {
                sanitizedLines.append(sanitized)
            }
        }
        return sanitizedLines.joined(separator: "\n")
    }

    /// Sanitizes a single line. Returns a redacted/suppressed string.
    static func sanitizeLine(_ line: String) -> String? {
        // 1. Suppress lines with Authorization or Bearer tokens anywhere on the line
        if line.range(of: "(?i)\\bauthorization\\s*:\\s*\\S+", options: .regularExpression) != nil
            || line.range(of: "(?i)\\bbearer\\s+[A-Za-z0-9_\\-\\.]+", options: .regularExpression) != nil {
            return "[REDACTED SENSITIVE LINE]"
        }

        // 2. Suppress or redact lines containing explicit serial number identifiers
        let serialLinePattern = "(?i)^\\s*(?:usb\\s*)?serial(?:\\s*number|_number)?\\s*[:=]\\s*.+$|(?i)^\\s*kUSBSerialNumberString\\b.*|(?i)^\\s*USB Serial Number\\s*:.*"
        if line.range(of: serialLinePattern, options: .regularExpression) != nil {
            return "[REDACTED SERIAL]"
        }

        // 3. In-line sanitization for URLs and queries
        var result = line

        // 3a. Redact URL userinfo passwords: e.g. http://user:secret@host -> http://user:[REDACTED]@host
        let userinfoRegex = try? NSRegularExpression(pattern: "([a-zA-Z][a-zA-Z0-9+.-]*://[^:/\\s@]+):([^@/\\s]+)@", options: [])
        if let regex = userinfoRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1:[REDACTED]@")
        }

        // 3b. Redact sensitive query parameters and serial numbers in URLs: ?password=..., ?passphrase=..., ?token=..., ?serial=...
        let queryRegex = try? NSRegularExpression(pattern: "(?i)([?&](?:password|passwd|passphrase|secret|token|api_key|apikey|serial)(?:=|%3D))[^&\\s\"']+", options: [])
        if let regex = queryRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1[REDACTED]")
        }

        // 3c. Redact inline serial parameter if remaining (e.g. serial="...")
        let inlineSerialRegex = try? NSRegularExpression(pattern: "(?i)\\bserial(?:_number)?\\s*[:=]\\s*[\"']?[A-Za-z0-9_-]+[\"']?", options: [])
        if let regex = inlineSerialRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "serial: [REDACTED]")
        }

        // 4. Suppress lines defining unredacted credential/token/secret/password/passphrase fields or assignments.
        // Matches e.g. password=..., password: ..., "password": ..., passphrase=..., password%3D...
        // Does NOT match harmless explanatory sentences like "No password is saved." or already redacted query values.
        let sensitiveFieldPattern = "(?i)(?:^|[\\s\"'{(\\[,;])(?:password|passwd|passphrase|secret|token|credential|credentials|api_key|apikey|private_key|auth_token|access_token|refresh_token)[\"']?\\s*[:=]\\s*(?!\\[REDACTED\\])|(?i)\\b(?:password|passwd|passphrase|secret|token|credential|api_key|apikey)%3D(?!\\[REDACTED\\])"
        if result.range(of: sensitiveFieldPattern, options: .regularExpression) != nil {
            return "[REDACTED SENSITIVE LINE]"
        }

        return result
    }

    // MARK: - Helper Status Parsing

    struct HelperStatus {
        let loaded: Bool
        let state: String
        let lastResult: String
    }

    /// Queries the launchd system domain once for the USB helper service.
    /// Extracts only state and the last exit or signal result; never dumps the full service or environment.
    static func queryHelperService(label: String = USBPrinterService.label) -> HelperStatus {
        let result = Shell.run(Tool.launchctl, ["print", "system/\(label)"])
        return parseHelperStatus(ok: result.ok, stdout: result.stdout, stderr: result.stderr)
    }

    static func parseHelperStatus(ok: Bool, stdout: String, stderr: String) -> HelperStatus {
        if !ok {
            let trimmedErr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let isMissing = trimmedErr.localizedCaseInsensitiveContains("could not find service")
                || trimmedErr.localizedCaseInsensitiveContains("no such process")
                || trimmedErr.localizedCaseInsensitiveContains("not found")
            if isMissing {
                let detail = trimmedErr.isEmpty ? "service not found" : trimmedErr
                return HelperStatus(loaded: false, state: "off (\(detail))", lastResult: "no job/no result")
            } else {
                let detail = trimmedErr.isEmpty ? "status unavailable" : trimmedErr
                return HelperStatus(loaded: false, state: "unknown (status unavailable: \(detail))", lastResult: "unknown (status unavailable)")
            }
        }

        var parsedState = "unknown"
        var parsedLastResult = "no job/no result"

        let lines = stdout.components(separatedBy: .newlines)
        var depth = 0
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let fieldDepth = depth
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            guard fieldDepth == 1 else { continue }
            if parsedState == "unknown" && line.hasPrefix("state = ") {
                parsedState = String(line.dropFirst("state = ".count))
            } else if line.hasPrefix("last exit code = ") {
                let code = String(line.dropFirst("last exit code = ".count))
                if code == "0" {
                    parsedLastResult = "exit 0 (success)"
                } else if code == "(never exited)" {
                    parsedLastResult = "(never exited)"
                } else {
                    parsedLastResult = "exit \(code)"
                }
            } else if line.hasPrefix("last terminating signal = ") {
                let sig = String(line.dropFirst("last terminating signal = ".count))
                parsedLastResult = "signal \(sig)"
            } else if line.hasPrefix("last termination signal = ") {
                let sig = String(line.dropFirst("last termination signal = ".count))
                parsedLastResult = "signal \(sig)"
            } else if line.hasPrefix("last exit reason = ") {
                let reason = String(line.dropFirst("last exit reason = ".count))
                if parsedLastResult == "no job/no result" {
                    parsedLastResult = reason
                }
            }
        }

        return HelperStatus(loaded: true, state: parsedState, lastResult: parsedLastResult)
    }

    // MARK: - Log Reading

    /// Reads up to maxLines from path using tail.
    /// Distinguishes between missing file, unreadable file, empty file, and readable content.
    static func tailFile(path: String, maxLines: Int = 50) -> [String] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            return ["(missing - file does not exist)"]
        }
        if !fm.isReadableFile(atPath: path) {
            return ["(unreadable - permission denied)"]
        }
        let result = Shell.run(Tool.path("tail"), ["-n", String(maxLines), path])
        if !result.ok {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if err.localizedCaseInsensitiveContains("permission denied") {
                return ["(unreadable - permission denied)"]
            } else if err.localizedCaseInsensitiveContains("no such file") {
                return ["(missing - file does not exist)"]
            } else {
                return ["(unreadable - \(err.isEmpty ? "status \(result.status)" : err))"]
            }
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ["(empty - no log entries)"]
        }
        let lines = result.stdout.components(separatedBy: .newlines)
        let filtered = lines.last?.isEmpty == true ? lines.dropLast() : lines[...]
        return Array(filtered)
    }

    // MARK: - Activity Formatting

    /// Formats in-memory log entries into bounded, chronological output lines.
    /// Strictly caps total emitted lines even when log messages contain embedded newlines.
    static func formatActivityLog(_ entries: [LogEntry], maxLines: Int = 50) -> [String] {
        if entries.isEmpty {
            return ["(no activity recorded in this session)"]
        }
        // AppState.activity is stored newest first. Format in chronological order:
        var lines: [String] = []
        for entry in entries.reversed() {
            let entryLines = entry.message.components(separatedBy: .newlines)
            if entryLines.isEmpty { continue }
            lines.append("[\(entry.timestamp)] [\(entry.kind.rawValue.uppercased())] \(entryLines[0])")
            for sub in entryLines.dropFirst() {
                lines.append("    \(sub)")
            }
        }
        if lines.isEmpty {
            return ["(no activity recorded in this session)"]
        }
        if lines.count > maxLines {
            return Array(lines.suffix(maxLines))
        }
        return lines
    }

    // MARK: - Report Generation

    static func generate(
        appVersion: String? = nil,
        activitySnapshot: [LogEntry] = [],
        helperLabel: String = USBPrinterService.label,
        stdoutLogPath: String = "/var/log/printer-studio-usb.log",
        stderrLogPath: String = "/var/log/printer-studio-usb.err.log",
        tailLines: Int = 50
    ) -> String {
        var sections: [String] = []

        // 1. Header
        let divider = String(repeating: "─", count: 68)
        sections.append("""
        \(divider)
        Printer Studio KH — Error Report
        \(ISO8601DateFormatter().string(from: Date()))
        \(divider)
        """)

        // 2. Application
        let version: String = {
            if let v = appVersion { return v }
            let info = Bundle.main.infoDictionary
            let short = info?["CFBundleShortVersionString"] as? String
            let build = info?["CFBundleVersion"] as? String
            if let short, let build { return "\(short) (build \(build))" }
            if let short { return short }
            return "unknown"
        }()
        let bundleID = Bundle.main.bundleIdentifier ?? "com.theng12.printerstudio"
        sections.append("""
        === Application ===
        Version:         \(version)
        Bundle ID:       \(bundleID)
        """)

        // 3. System
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        let arch = "Intel (x86_64)"
        #else
        let arch = "unknown"
        #endif
        sections.append("""
        === System ===
        macOS:           \(osVersion)
        Architecture:    \(arch)
        """)

        // 4. USB Printer (HP Laser 107a)
        let laser = Driver.connectedLaser107a
        let laserSeen = laser != nil ? "yes" : "no"
        let held = Driver.ippusbdHoldingPrinter() ? "yes" : "no"
        let usbDetails = [
            "USB printer seen (HP Laser 107a): \(laserSeen)",
            "Held by ippusbd:                  \(held)"
        ]
        sections.append("""
        === USB Printer (HP Laser 107a) ===
        \(usbDetails.joined(separator: "\n"))
        """)

        // 5. USB Helper Service
        let helper = queryHelperService(label: helperLabel)
        let helperState = helper.loaded ? "on (\(helper.state))" : helper.state
        sections.append("""
        === USB Helper Service ===
        Service label:   \(helperLabel)
        Status:          \(helperState)
        Last result:     \(helper.lastResult)
        """)

        // 6. Helper stdout log
        let stdoutLines = tailFile(path: stdoutLogPath, maxLines: tailLines)
        sections.append("""
        === Helper Log: stdout (\(stdoutLogPath)) ===
        \(stdoutLines.joined(separator: "\n"))
        """)

        // 7. Helper stderr log
        let stderrLines = tailFile(path: stderrLogPath, maxLines: tailLines)
        sections.append("""
        === Helper Log: stderr (\(stderrLogPath)) ===
        \(stderrLines.joined(separator: "\n"))
        """)

        // 8. App Activity (this session)
        let activityLines = formatActivityLog(activitySnapshot, maxLines: tailLines)
        sections.append("""
        === App activity (this session) ===
        \(activityLines.joined(separator: "\n"))
        """)

        // Capture the failing label queue's negotiated format and geometry, not just HP USB status.
        for printer in CUPS.listPrinters() {
            let attributes = CUPS.attributes(of: printer.name)
            let keys = ["printer-info", "printer-make-and-model", "printer-is-shared",
                        "printer-state-reasons", "document-format-supported", "media-default",
                        "media-supported", "print-scaling-default"]
            var details = keys.map { "\($0): \(attributes[$0] ?? "not reported")" }
            if let ppd = PageSizeInstaller.readPPD(queue: printer.name) {
                details += ppd.components(separatedBy: .newlines).filter {
                    $0.hasPrefix("*cupsFilter") || $0.hasPrefix("*DefaultPageSize:") ||
                    $0.hasPrefix("*DefaultResolution:") || $0.hasPrefix("*cupsModelNumber:")
                }
            } else {
                details.append("Driver PPD: unavailable")
            }
            sections.append("=== Print path: \(printer.displayName) ===\n" + details.joined(separator: "\n"))
        }
        sections.append(divider)

        let fullRawReport = sections.joined(separator: "\n\n")
        return sanitize(fullRawReport)
    }
}
