import Foundation

/// Focused tests for the AirPrint advertisement installer.
///
/// Everything runs in a temporary directory. No print queue is touched, no
/// Bonjour service is published and no launchd job is loaded — the tests
/// only exercise the file handling, which is where the helper migration and
/// the "keep the old copy" rule live.
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
        if let helper = bundledHelperPath {
            setenv("PRINTER_STUDIO_BUNDLED_HELPER", helper, 1)
        }

        testSharingFailureDoesNotInstall()
        testSharingPreparedBeforeInstall()
        testInstallCopiesHelperAndAgent()
        testTrashKeepsOldScript()
        testTrashKeepsOldAgent()
        testRefreshDoesNothingWhenOff()
        testRefreshMigratesOldStyleAgent()
        testRefreshLeavesNewStyleAlone()

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

    /// The helper bundle the app would ship, supplied by the test runner.
    static var bundledHelperPath: String? {
        CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
    }

    static var installedHelperExecutable: URL {
        DriverInstaller.airPrintSupportDirectory
            .appendingPathComponent("Printer Studio KH Helper.app")
            .appendingPathComponent("Contents/MacOS/Printer Studio KH Helper")
    }

    static var agentPlist: URL { URL(fileURLWithPath: DriverInstaller.airPrintAgentPath) }

    static func write(_ text: String, to url: URL) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func files(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted()
    }

    static func agentArguments() -> [String]? {
        guard let data = try? Data(contentsOf: agentPlist),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return plist["ProgramArguments"] as? [String]
    }

    static func agentBundleIdentifiers() -> [String]? {
        guard let data = try? Data(contentsOf: agentPlist),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return plist["AssociatedBundleIdentifiers"] as? [String]
    }

    static func trashFiles() -> [String] {
        let trash = DriverInstaller.airPrintSupportDirectory.appendingPathComponent("_trash")
        return files(in: trash)
    }

    static let sharingOK = {
        CommandResult(status: 0, stdout: "Printer Sharing is on.", stderr: "")
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

    static func testInstallCopiesHelperAndAgent() {
        // An old installation left its shell worker behind.
        write("#!/bin/bash\n", to: URL(fileURLWithPath: DriverInstaller.airPrintScriptPath))

        let result = DriverInstaller.installAirPrintBridge(prepareSharing: sharingOK)
        assertTest(result.ok, "the advertisement installs into the scratch directory")
        assertTest(FileManager.default.fileExists(atPath: installedHelperExecutable.path),
                   "Printer Studio KH Helper.app is copied into the support directory")
        assertTest(agentArguments() == [installedHelperExecutable.path, "bridge"],
                   "the agent runs the helper with bridge")
        assertTest(agentBundleIdentifiers() == ["com.theng12.printerstudio.helper"],
                   "the agent is attributed to the helper bundle")
        assertTest(!FileManager.default.fileExists(
            atPath: DriverInstaller.airPrintScriptPath),
                   "the old shell advertisement is no longer installed")
        assertTest(trashFiles().contains { $0.hasPrefix("airprint-bridge.sh") },
                   "the old shell advertisement is kept in _trash")

        // A second run must not break the installed helper or agent.
        let second = DriverInstaller.installAirPrintBridge(prepareSharing: sharingOK)
        assertTest(second.ok, "a second install succeeds")
        assertTest(FileManager.default.fileExists(atPath: installedHelperExecutable.path),
                   "a second install keeps the helper")
        assertTest(agentArguments() == [installedHelperExecutable.path, "bridge"],
                   "a second install keeps the same agent program")
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
        _ = DriverInstaller.removeAirPrintBridge()
        assertTest(!DriverInstaller.isAirPrintInstalled, "the advertisement is off before the refresh")

        let result = DriverInstaller.refreshAirPrintBridgeIfOutdated()
        assertTest(result.ok, "a refresh with the advertisement off succeeds")
        assertTest(result.stdout.contains("is off"),
                   "a refresh with the advertisement off says so")
    }

    static func testRefreshMigratesOldStyleAgent() {
        let installed = DriverInstaller.installAirPrintBridge(prepareSharing: sharingOK)
        assertTest(installed.ok, "the helper installs before migration")
        assertTest(FileManager.default.fileExists(atPath: installedHelperExecutable.path),
                   "the helper is present before migration")

        // Recreate the 1.0.14 shape: bash, the old script, no attribution.
        write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.theng12.printerstudio.airprint</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(DriverInstaller.airPrintScriptPath)</string>
                <string>run</string>
            </array>
        </dict>
        </plist>
        """, to: agentPlist)
        write("#!/bin/bash\n", to: URL(fileURLWithPath: DriverInstaller.airPrintScriptPath))

        let result = DriverInstaller.refreshAirPrintBridgeIfOutdated()
        assertTest(result.ok, "a refresh of an old-style agent succeeds")
        assertTest(agentArguments() == [installedHelperExecutable.path, "bridge"],
                   "the old-style agent is rewritten to run the helper")
        assertTest(agentBundleIdentifiers() == ["com.theng12.printerstudio.helper"],
                   "the migrated agent is attributed to the helper bundle")
        assertTest(!FileManager.default.fileExists(
            atPath: DriverInstaller.airPrintScriptPath),
                   "migration retires the old shell advertisement")
        assertTest(result.stdout.contains("updated"), "the migration says it updated the agent")
    }

    static func testRefreshLeavesNewStyleAlone() {
        let result = DriverInstaller.refreshAirPrintBridgeIfOutdated()
        assertTest(result.ok, "a refresh of a helper installation succeeds")
        assertTest(agentArguments() == [installedHelperExecutable.path, "bridge"],
                   "the helper agent is left alone")
        assertTest(result.stdout.contains("up to date"),
                   "an up-to-date advertisement says it is up to date")
    }
}
