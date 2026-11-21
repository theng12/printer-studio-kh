import Foundation
import ServiceManagement

@main
struct TestLoginItem {
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
        print("Running Login Item Test Suite…\n")
        let enabled = LoginItem.message(for: .enabled)
        let approval = LoginItem.message(for: .requiresApproval)
        let notRegistered = LoginItem.message(for: .notRegistered)
        let notFound = LoginItem.message(for: .notFound)

        assertTest(enabled == "Printer Studio KH will open at login.", "Enabled says it will open at login")
        assertTest(approval != enabled, "Waiting for approval is never the success sentence")
        assertTest(approval.contains("System Settings") && approval.contains("Login Items"),
                   "Waiting for approval names the one action")
        assertTest(approval.contains("cannot open at login"),
                   "Waiting for approval says plainly that it will not open yet")
        assertTest(notRegistered.contains("not set to open at login"),
                   "Not registered says it is off, not that it worked")
        assertTest(notFound.contains("Applications"),
                   "Not found tells the person to move the app to Applications")
        assertTest(Set([enabled, approval, notRegistered, notFound]).count == 4,
                   "Every state has its own sentence")

        // Three launches, in order. The no-op is the absence of a call, not silence.
        let first = LoginItem.registrationAction(storedBuild: nil, currentBuild: "40",
                                                 isEnabled: false, isConfigured: false)
        assertTest(first == .register, "First launch: first enable registers and is marked")
        let second = LoginItem.registrationAction(storedBuild: "40", currentBuild: "40",
                                                  isEnabled: true, isConfigured: true)
        assertTest(second == .none,
                   "Second launch after the marker is written: no unregister, no register, no write")
        let afterUpdate = LoginItem.registrationAction(storedBuild: "40", currentBuild: "41",
                                                       isEnabled: true, isConfigured: true)
        assertTest(afterUpdate == .reRegister,
                   "Launch after a version change: exactly one unregister+register, then the marker moves")
        let settled = LoginItem.registrationAction(storedBuild: "41", currentBuild: "41",
                                                   isEnabled: true, isConfigured: true)
        assertTest(settled == .none, "The launch after that is quiet again")
        let unmarked = LoginItem.registrationAction(storedBuild: nil, currentBuild: "40",
                                                    isEnabled: true, isConfigured: true)
        assertTest(unmarked == .reRegister,
                   "An enabled item with no marker is refreshed once, never left stale")
        let off = LoginItem.registrationAction(storedBuild: "40", currentBuild: "40",
                                               isEnabled: false, isConfigured: true)
        assertTest(off == .register, "An item that is off is enabled, not re-registered")

        print("\nSummary: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
