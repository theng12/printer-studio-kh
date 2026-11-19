import AppKit

/// Re-reads the app's status when it is brought forward.
///
/// The printer and queue state used to be read once at launch and then held: a
/// queue that stopped, or a job that arrived from a phone, stayed invisible
/// until Refresh was pressed. Event-driven, so nothing runs while the app sits
/// in the background. Returns the token so the caller can stop observing.
enum LiveStatus {
    static func observeActivation(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { _ in handler() }
    }
}
