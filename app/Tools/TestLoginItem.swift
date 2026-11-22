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
        func action(_ choice: LoginItem.Choice, _ stored: String?, _ current: String,
                    _ enabled: Bool) -> LoginItem.RegistrationAction {
            LoginItem.registrationAction(choice: choice, storedBuild: stored,
                                         currentBuild: current, isEnabled: enabled)
        }
        assertTest(action(.unset, nil, "40", false) == .register,
                   "First launch: nobody has chosen, so the default registers and is marked")
        assertTest(action(.on, "40", "40", true) == .none,
                   "Second launch after the marker is written: no unregister, no register, no write")
        assertTest(action(.on, "40", "41", true) == .reRegister,
                   "Launch after a version change: exactly one unregister+register, then the marker moves")
        assertTest(action(.on, "41", "41", true) == .none, "The launch after that is quiet again")
        assertTest(action(.on, nil, "40", true) == .reRegister,
                   "An enabled item with no marker is refreshed once, never left stale")
        assertTest(action(.on, "40", "41", false) == .register,
                   "An item the person turned on that vanished after an update is restored once")
        assertTest(action(.on, "40", "40", false) == .none,
                   "An item removed in System Settings under this build stays removed")

        // The person's own off is not overridden, ever — the state-flipping bug.
        assertTest(action(.off, "40", "40", false) == .none,
                   "Person enables, then disables: the next launch does nothing")
        assertTest(action(.off, "39", "40", false) == .none,
                   "A person's off survives a version change with no call")
        assertTest(action(.off, nil, "40", true) == .none,
                   "Even a stray enabled state never overrides a stored off")

        // One-time migration from the old pair of facts to the tri-state.
        assertTest(LoginItem.choiceValue(stored: "on", configured: false, isEnabled: false) == .on,
                   "A stored on is never re-inferred")
        assertTest(LoginItem.choiceValue(stored: nil, configured: true, isEnabled: false) == .off,
                   "An old configured-but-off install migrates to a person's off")
        assertTest(LoginItem.choiceValue(stored: nil, configured: true, isEnabled: true) == .on,
                   "An old configured-and-on install migrates to on")
        assertTest(LoginItem.choiceValue(stored: nil, configured: false, isEnabled: false) == .unset,
                   "A fresh install has made no choice")

        print("\nSummary: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
