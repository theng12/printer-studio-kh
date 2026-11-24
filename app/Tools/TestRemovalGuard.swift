import Foundation

/// The decision behind "Remove everything": a confirmation that exists, is fresh, and is
/// issued by the dialog. The harness prints one line per property so a failure names itself.
@main
struct TestRemovalGuard {
    static var failures = 0

    static func check(_ name: String, _ condition: Bool) {
        print(condition ? "PASS: \(name)" : "FAIL: \(name)")
        if !condition { failures += 1 }
    }

    static func main() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        check("no confirmation is a refusal", !RemovalGuard.permits(nil, now: now))
        check("a fresh confirmation permits the removal",
              RemovalGuard.permits(RemovalGuard.issue(now: now), now: now))
        check("a confirmation still inside its window permits",
              RemovalGuard.permits(RemovalGuard.issue(now: now),
                                   now: now.addingTimeInterval(RemovalGuard.window - 1)))
        check("a confirmation older than its window is refused",
              !RemovalGuard.permits(RemovalGuard.issue(now: now),
                                    now: now.addingTimeInterval(RemovalGuard.window + 1)))
        check("a confirmation dated in the future is refused",
              !RemovalGuard.permits(RemovalGuard.issue(now: now.addingTimeInterval(5)), now: now))
        let token = RemovalGuard.issue(now: now)
        check("the same token is the same authorisation", token == token)

        if failures > 0 {
            print("FAILED: \(failures) check(s)")
            exit(1)
        }
        print("PASS: removal guard")
    }
}
