import AppKit

/// Proves the shipped activation hook: bringing the app forward fires the
/// re-read, and a different notification does not.
@main
struct TestLiveStatus {
    static func main() {
        var fired = 0
        let token = LiveStatus.observeActivation { fired += 1 }

        // A different notification must not trigger it.
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        precondition(fired == 0, "an unrelated notification fired the re-read")
        print("PASS: only becoming active triggers the re-read")

        // Posted on the main thread with a .main queue, delivery is synchronous.
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        precondition(fired == 1, "becoming active did not trigger the re-read")
        print("PASS: bringing the app forward re-reads the status")

        NotificationCenter.default.removeObserver(token)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        precondition(fired == 1, "the re-read kept running after it was stopped")
        print("PASS: the observer stops when it is removed")
    }
}
