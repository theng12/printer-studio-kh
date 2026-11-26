import Foundation

@main
struct TestErrorReport {
    static var passed = 0
    static var failed = 0

    static func assertTest(_ condition: Bool, _ name: String) {
        if condition {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ FAIL: \(name)")
        }
    }

    static func main() {
        print("Running Diagnostic Error Report Test Suite…")

        testSanitizerUserInfo()
        testSanitizerQueryParameters()
        testSanitizerFieldSuppression()
        testSanitizerPrivateKeyBlock()
        testSanitizerHarmlessText()
        testSanitizerSerialRedaction()
        testActivityLogBounding()
        testHelperStatusParsing()
        testTailFileFixtures()
        testEndToEndReport()

        print("\nSummary: \(passed) passed, \(failed) failed")
        if failed > 0 {
            exit(1)
        }
    }

    // MARK: - Tests

    static func testSanitizerUserInfo() {
        let p1 = ["sec", "ret", "123"].joined()
        let input = "Connecting to http://admin:\(p1)@192.168.1.100:631/printers/laser"
        let sanitized = DiagnosticReport.sanitize(input)
        assertTest(sanitized == "Connecting to http://admin:[REDACTED]@192.168.1.100:631/printers/laser",
                   "Sanitizer redacts URL userinfo password")
        assertTest(!sanitized.contains(p1), "Secret value does not appear in sanitized output")
    }

    static func testSanitizerQueryParameters() {
        let p = ["s", "e", "c", "r", "e", "t"].joined()
        let ph = ["m", "y", "p", "a", "s", "s"].joined()
        let t = ["t", "o", "k", "1", "2", "3"].joined()
        let s = ["s", "e", "r", "4", "5", "6"].joined()
        let input = "GET /status?user=alice&password=\(p)&passphrase=\(ph)&token=\(t)&serial=\(s)&format=json"
        let sanitized = DiagnosticReport.sanitize(input)
        assertTest(sanitized == "GET /status?user=alice&password=[REDACTED]&passphrase=[REDACTED]&token=[REDACTED]&serial=[REDACTED]&format=json",
                   "Sanitizer redacts sensitive URL query parameters (password, passphrase, token, serial)")
        assertTest(!sanitized.contains(p) && !sanitized.contains(ph) && !sanitized.contains(t) && !sanitized.contains(s),
                   "Query secret values are absent from output")
    }

    static func testSanitizerFieldSuppression() {
        let sensitiveLines = [
            "password = \"val\"",
            "\"password\": \"val\"",
            "password: val",
            "password%3Dval",
            "passphrase = \"my_passphrase\"",
            "\"passphrase\": \"val\"",
            "passphrase: val",
            "token = 12345",
            "\"token\": \"abc\"",
            "secret: secret123",
            "api_key: key123",
            "apikey = key999",
            "private_key = mykey",
            "Authorization: Bearer mytoken",
            "bearer token123",
            "[14:20:11] [INFO] Authorization: Bearer timestamped_token",
            "[14:20:12] [INFO] Bearer token_with_prefix"
        ]

        var allSuppressed = true
        for line in sensitiveLines {
            let res = DiagnosticReport.sanitize(line)
            if res != "[REDACTED SENSITIVE LINE]" {
                allSuppressed = false
            }
        }
        assertTest(allSuppressed, "Sanitizer suppresses entire lines containing sensitive fields, passphrases, and timestamp-prefixed auth headers")
    }

    static func testSanitizerPrivateKeyBlock() {
        let privateKey = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA0Y1+examplePrivateContentLine1
        MIIEowIBAAKCAQEA0Y1+examplePrivateContentLine2
        -----END RSA PRIVATE KEY-----
        """
        let sanitized = DiagnosticReport.sanitize(privateKey)
        assertTest(!sanitized.contains("examplePrivateContentLine1"), "Private key body line 1 is suppressed")
        assertTest(!sanitized.contains("examplePrivateContentLine2"), "Private key body line 2 is suppressed")
        assertTest(sanitized == "[REDACTED SENSITIVE LINE]\n[REDACTED SENSITIVE LINE]",
                   "Private key block is completely suppressed from BEGIN through END")
    }

    static func testSanitizerHarmlessText() {
        let harmless = [
            "Printer Studio KH 1.0.2 (build 3)",
            "macOS: Version 14.5 (Build 23F79)",
            "Architecture: Apple Silicon (arm64)",
            "No password is saved.",
            "No administrator password is needed.",
            "Automatic USB release needs administrator approval once without saving a password.",
            "CUPS version 2.3.4",
            "data = try PropertyListSerialization.data(fromPropertyList: plist)",
            "USB printer seen (HP Laser 107a): yes",
            "Status: on (running)"
        ]

        var allPreserved = true
        for line in harmless {
            let res = DiagnosticReport.sanitize(line)
            if res != line {
                allPreserved = false
            }
        }
        assertTest(allPreserved, "Sanitizer preserves harmless diagnostic lines and explanatory text")
    }

    static func testSanitizerSerialRedaction() {
        let s1 = ["C", "N", "B", "1", "2", "3", "4", "5"].joined()
        let serialLines = [
            "Serial Number: \(s1)",
            "serialNumber: \(s1)",
            "serial_number = \(s1)",
            "kUSBSerialNumberString: \(s1)",
            "USB Serial Number: \(s1)"
        ]

        var allRedacted = true
        for line in serialLines {
            let res = DiagnosticReport.sanitize(line)
            if res != "[REDACTED SERIAL]" {
                allRedacted = false
            }
        }
        assertTest(allRedacted, "Sanitizer redacts hardware serial number lines")

        let uriLine = "deviceURI: usb://HP/Laser%20107a?serial=\(s1)"
        let sanitizedUri = DiagnosticReport.sanitize(uriLine)
        assertTest(sanitizedUri == "deviceURI: usb://HP/Laser%20107a?serial=[REDACTED]",
                   "Sanitizer redacts USB device URI serial parameter")
    }

    static func testActivityLogBounding() {
        // Test empty
        let empty = DiagnosticReport.formatActivityLog([])
        assertTest(empty == ["(no activity recorded in this session)"],
                   "Empty activity log reports placeholder")

        // Test with multi-line entries exceeding maxLines
        // In AppState, entries are inserted at index 0 (newest first).
        var entries: [LogEntry] = []
        for i in 1...15 {
            let multilineMsg = "Action \(i) started\nDetails line 1 for action \(i)\nDetails line 2 for action \(i)\nDetails line 3 for action \(i)\nAction \(i) completed"
            entries.insert(LogEntry(multilineMsg, kind: i % 2 == 0 ? .info : .success), at: 0)
        }

        // Bounded at 50 lines
        let formatted = DiagnosticReport.formatActivityLog(entries, maxLines: 50)
        assertTest(formatted.count == 50,
                   "Activity formatting caps total emitted lines at maxLines even with embedded newlines")

        // Verify chronological order (oldest entry action 1 comes before newest entry action 15)
        let firstLine = formatted.first ?? ""
        let lastLine = formatted.last ?? ""
        assertTest(!firstLine.contains("Action 15") && lastLine.contains("Action 15"),
                   "Activity formatting maintains chronological order")
    }

    static func testHelperStatusParsing() {
        // 1. Missing service error
        let failedMissing = DiagnosticReport.parseHelperStatus(ok: false, stdout: "", stderr: "Could not find service com.theng12.printerstudio.usb in domain for system")
        assertTest(!failedMissing.loaded && failedMissing.lastResult == "no job/no result" && failedMissing.state == "off (Could not find service com.theng12.printerstudio.usb in domain for system)",
                   "Helper status parsing handles missing service as off/no job")

        // 2. Permission failure / non-missing failure
        let failedPerm = DiagnosticReport.parseHelperStatus(ok: false, stdout: "", stderr: "Permission denied")
        assertTest(!failedPerm.loaded && failedPerm.state == "unknown (status unavailable: Permission denied)" && failedPerm.lastResult == "unknown (status unavailable)",
                   "Helper status parsing maps permission/unexpected errors to unknown unavailable")

        let badRequest = DiagnosticReport.parseHelperStatus(ok: false, stdout: "", stderr: "Bad request")
        assertTest(badRequest.state.hasPrefix("unknown"), "Generic bad request does not claim helper is off")
        let nestedOnly = DiagnosticReport.parseHelperStatus(ok: true, stdout: "job = {\n endpoints = {\n state = active\n }\n}", stderr: "")
        assertTest(nestedOnly.state == "unknown", "Nested state alone does not become the job state")

        // 3. Running, last exit 0, with nested endpoint state = active
        let mockRunningWithNested = """
        system/com.theng12.printerstudio.usb = {
            state = running
            last exit code = 0
            endpoints = {
                "com.theng12.sub" = {
                    state = active
                }
            }
        }
        """
        let parsedRunning = DiagnosticReport.parseHelperStatus(ok: true, stdout: mockRunningWithNested, stderr: "")
        assertTest(parsedRunning.loaded && parsedRunning.state == "running" && parsedRunning.lastResult == "exit 0 (success)",
                   "Helper status parsing extracts top-level state and does not overwrite with nested state=active")

        // 4. Real launchctl key: last terminating signal = Terminated: 15
        let mockTerminatingSignal = """
        system/com.theng12.printerstudio.usb = {
            state = waiting
            last terminating signal = Terminated: 15
        }
        """
        let parsedTerminating = DiagnosticReport.parseHelperStatus(ok: true, stdout: mockTerminatingSignal, stderr: "")
        assertTest(parsedTerminating.lastResult == "signal Terminated: 15",
                   "Helper status parsing handles real launchctl key 'last terminating signal = Terminated: 15'")

        // 5. Waiting, never exited
        let mockWaiting = """
        system/com.theng12.printerstudio.usb = {
            state = waiting
            last exit code = (never exited)
        }
        """
        let parsedWaiting = DiagnosticReport.parseHelperStatus(ok: true, stdout: mockWaiting, stderr: "")
        assertTest(parsedWaiting.loaded && parsedWaiting.state == "waiting" && parsedWaiting.lastResult == "(never exited)",
                   "Helper status parsing handles waiting state and (never exited)")

        // 6. Non-zero exit code
        let mockExitErr = """
        system/com.theng12.printerstudio.usb = {
            state = waiting
            last exit code = 1
        }
        """
        let parsedExitErr = DiagnosticReport.parseHelperStatus(ok: true, stdout: mockExitErr, stderr: "")
        assertTest(parsedExitErr.lastResult == "exit 1", "Helper status parsing handles non-zero exit code")

        // 7. Missing state line defaults to unknown (not running)
        let mockNoState = """
        system/com.theng12.printerstudio.usb = {
            runs = 0
        }
        """
        let parsedNoState = DiagnosticReport.parseHelperStatus(ok: true, stdout: mockNoState, stderr: "")
        assertTest(parsedNoState.state == "unknown", "Helper status parsing does not default to running when state is missing")
    }

    static func testTailFileFixtures() {
        let fm = FileManager.default
        // Fixtures belong under TMPDIR; a checkout never gets a _trash.
        let trashBase = fm.temporaryDirectory.appendingPathComponent("test-error-report-fixtures-\(ProcessInfo.processInfo.globallyUniqueString)")
        try? fm.createDirectory(at: trashBase, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: trashBase) }

        // 1. Missing file
        let missingPath = trashBase.appendingPathComponent("nonexistent.log").path
        let missingResult = DiagnosticReport.tailFile(path: missingPath)
        assertTest(missingResult == ["(missing - file does not exist)"],
                   "Tail file reports missing status for non-existent path")

        // 2. Empty file
        let emptyPath = trashBase.appendingPathComponent("empty.log").path
        try? "".write(toFile: emptyPath, atomically: true, encoding: .utf8)
        let emptyResult = DiagnosticReport.tailFile(path: emptyPath)
        assertTest(emptyResult == ["(empty - no log entries)"],
                   "Tail file reports empty status for empty path")

        // 3. Populated file (> 50 lines)
        let popPath = trashBase.appendingPathComponent("populated.log").path
        let lines = (1...70).map { "Log entry line \($0)" }.joined(separator: "\n")
        try? lines.write(toFile: popPath, atomically: true, encoding: .utf8)
        let popResult = DiagnosticReport.tailFile(path: popPath, maxLines: 50)
        assertTest(popResult.count == 50 && popResult.last == "Log entry line 70" && popResult.first == "Log entry line 21",
                   "Tail file extracts exactly the last 50 lines of populated file")

        // 4. Unreadable file (chmod 000)
        let unreadablePath = trashBase.appendingPathComponent("unreadable.log").path
        try? "test log content".write(toFile: unreadablePath, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadablePath)
        let unreadableResult = DiagnosticReport.tailFile(path: unreadablePath)
        assertTest(unreadableResult == ["(unreadable - permission denied)"],
                   "Tail file distinguishes unreadable file from missing file")

        // Reset permissions before finishing so trash is inspectable
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadablePath)
    }

    static func testEndToEndReport() {
        // Test fallback version without Bundle is unknown
        let reportFallback = DiagnosticReport.generate(appVersion: nil, activitySnapshot: [])
        assertTest(reportFallback.contains("Version:         unknown"),
                   "Report without explicit version or Bundle defaults to 'unknown' (never guessed)")

        let entry = LogEntry("Test session started", kind: .info)
        let report = DiagnosticReport.generate(
            appVersion: "1.0.2 (build 3)",
            activitySnapshot: [entry]
        )

        assertTest(report.contains("Printer Studio KH — Error Report"), "Report contains header")
        assertTest(report.contains("Version:         1.0.2 (build 3)"), "Report contains specified app version")
        assertTest(report.contains("=== System ==="), "Report contains system section")
        assertTest(report.contains("=== USB Printer (HP Laser 107a) ==="), "Report contains USB printer section")
        assertTest(report.contains("USB printer seen (HP Laser 107a):"), "Report checks HP Laser 107a USB presence")
        assertTest(!report.contains("Other USB printers:"), "Report does not query or list extra unrelated USB devices")
        assertTest(report.contains("=== USB Helper Service ==="), "Report contains USB helper section")
        assertTest(report.contains("=== Helper Log: stdout"), "Report contains helper stdout section")
        assertTest(report.contains("=== Helper Log: stderr"), "Report contains helper stderr section")
        assertTest(report.contains("=== App activity (this session) ==="), "Report contains session activity section")
        assertTest(report.contains("Test session started"), "Report includes session log entry")
    }
}
