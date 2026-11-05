import Foundation

/// Focused tests for the AirPrint advertisement installer.
///
/// Everything runs in a temporary directory. No print queue is touched, no
/// Bonjour service is published and no launchd job is loaded — the tests
/// only exercise the file handling, which is where the "keep the old copy"
/// rule lives.
@main
struct TestAirPrintInstaller {
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
        print("Running AirPrint Installer Test Suite…")

        // Everything runs in a scratch directory. The real installation on
        // this Mac is never read and never written.
        let root = makeRoot()
        setenv("PRINTER_STUDIO_AIRPRINT_TEST", "1", 1)
        setenv("PRINTER_STUDIO_SUPPORT_DIR", root.path, 1)
        setenv("PRINTER_STUDIO_BUNDLED_SCRIPT", bundledScriptPath, 1)

        testSharingFailureDoesNotInstall()
        testSharingPreparedBeforeInstall()
        testTrashKeepsOldScript()
        testTrashKeepsOldAgent()
        testRefreshDoesNothingWhenOff()
        testRefreshReplacesOutdatedScript()
        testRefreshLeavesMatchingScriptAlone()

        print("\nSummary: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }

    // MARK: - Helpers

    /// A scratch directory standing in for ~/Library/Application Support.
    static func makeRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("printer-studio-airprint-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The script the app would ship, taken from the checkout.
    static var bundledScriptPath: String {
        if CommandLine.arguments.count > 1 {
            return CommandLine.arguments[1]
        }
        return ""
    }

    static func write(_ text: String, to url: URL) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func files(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted()
    }

    // MARK: - Tests

    static func testSharingFailureDoesNotInstall() {
        let result = DriverInstaller.installAirPrintBridge(prepareSharing: {
            .failure("Printer Sharing permission was cancelled.")
        })
        assertTest(!result.ok, "sharing failure cannot report AirPrint success")
        assertTest(result.combined.contains("cancelled"), "sharing failure explains the cause")
        assertTest(!DriverInstaller.isAirPrintInstalled, "sharing failure leaves no installed agent")
    }

    static func testSharingPreparedBeforeInstall() {
        var prepared = false
        let result = DriverInstaller.installAirPrintBridge(prepareSharing: {
            assertTest(!DriverInstaller.isAirPrintInstalled, "sharing is prepared before installing the agent")
            prepared = true
            return CommandResult(status: 0, stdout: "Printer Sharing is on.", stderr: "")
        })
        assertTest(prepared && result.ok, "successful sharing preparation permits installation")
        _ = DriverInstaller.removeAirPrintBridge()
    }

    static func testTrashKeepsOldScript() {
        let root = makeRoot()
        let old = root.appendingPathComponent("old-script.sh")
        write("old contents", to: old)

        let kept = DriverInstaller.moveToTrashForTesting(old.path)

        assertTest(kept != nil, "a replaced script is moved, not deleted")
        assertTest(FileManager.default.fileExists(atPath: old.path) == false,
                   "the original path is empty afterwards")
        if let kept {
            let keptText = (try? String(contentsOf: URL(fileURLWithPath: kept), encoding: .utf8)) ?? ""
            assertTest(keptText == "old contents", "the old script is kept with its contents")
            assertTest(kept.contains("_trash"), "the old script is kept in _trash")
        }
    }

    static func testTrashKeepsOldAgent() {
        let root = makeRoot()
        let old = root.appendingPathComponent("agent.plist")
        write("<plist/>", to: old)

        let kept = DriverInstaller.moveToTrashForTesting(old.path)

        assertTest(kept != nil, "a removed agent is moved, not deleted")
        if let kept {
            assertTest(FileManager.default.fileExists(atPath: kept), "the old agent is still readable")
        }
    }

    static func testRefreshDoesNothingWhenOff() {
        // The advertisement is off on this Mac, so a refresh must do nothing.
        let result = DriverInstaller.refreshAirPrintBridgeIfOutdated()
        assertTest(result.ok, "a refresh with the advertisement off succeeds")
        assertTest(result.stdout.contains("is off"),
                   "a refresh with the advertisement off says so")
    }

    static func testRefreshReplacesOutdatedScript() {
        // The installed script differs from the bundled one, so the refresh
        // has to put the bundled one in place.
        let installed = URL(fileURLWithPath: DriverInstaller.airPrintScriptPath)
        guard let bundledPath = DriverInstaller.bundledAirPrintScript,
              let bundled = try? Data(contentsOf: URL(fileURLWithPath: bundledPath)) else {
            print("  - no bundled script, so the replace path is not exercised")
            return
        }
        // Put the advertisement in place, as the toggle would.
        let installed_ = DriverInstaller.installAirPrintBridge(prepareSharing: {
            CommandResult(status: 0, stdout: "Printer Sharing is on.", stderr: "")
        })
        assertTest(installed_.ok, "the advertisement installs into the scratch directory")
        assertTest(FileManager.default.fileExists(atPath: installed.path),
                   "the installed script is there")

        write("stale contents", to: installed)
        let result = DriverInstaller.refreshAirPrintBridgeIfOutdated()
        let after = (try? Data(contentsOf: installed)) ?? Data()
        assertTest(result.ok, "a refresh of an outdated script succeeds")
        assertTest(after == bundled, "the outdated script is replaced with the bundled one")
        assertTest(result.stdout.contains("updated"),
                   "a refresh of an outdated script says it updated")

        // The old script is kept, not deleted.
        let trash = URL(fileURLWithPath: DriverInstaller.airPrintScriptPath)
            .deletingLastPathComponent().appendingPathComponent("_trash")
        let kept = ((try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? [])
            .filter { $0.hasPrefix("airprint-bridge.sh") }
        assertTest(!kept.isEmpty, "the replaced script is kept in _trash")
    }

    static func testRefreshLeavesMatchingScriptAlone() {
        let installed = URL(fileURLWithPath: DriverInstaller.airPrintScriptPath)
        guard let bundledPath = DriverInstaller.bundledAirPrintScript,
              let bundled = try? Data(contentsOf: URL(fileURLWithPath: bundledPath)) else {
            print("  - no bundled script, so the up-to-date path is not exercised")
            return
        }
        try? bundled.write(to: installed)
        let result = DriverInstaller.refreshAirPrintBridgeIfOutdated()
        let after = (try? Data(contentsOf: installed)) ?? Data()
        assertTest(result.ok, "a refresh of an up-to-date script succeeds")
        assertTest(after == bundled, "an up-to-date script is left alone")
        assertTest(result.stdout.contains("up to date"),
                   "a refresh of an up-to-date script says it is up to date")
    }
}
