import Foundation
import Darwin

/// The in-app updater: Sparkle behind the studio's shim.
///
/// The shim holds this app through its own hold route before it fetches
/// anything, answers Sparkle's prompts itself (no window, no sheet), and reports
/// what it is doing: 0 idle, 1 updating, 2 relaunching. A refusal is a log line
/// with its reason, never a dialog and never a silent stop.
///
/// The shim's three entry points are looked up by name rather than linked through
/// a bridging header, so the app's test harnesses can compile this file without
/// carrying the C library. `build.sh` fails if the vendored archive stops
/// exporting them, which is where a rename would otherwise be lost.
enum SparkleUpdate {
    private typealias Start = @convention(c) () -> Int32
    private typealias LastError = @convention(c) () -> UnsafePointer<CChar>?
    private typealias SetCallback = @convention(c) (StateCallback?) -> Void
    private typealias StateCallback = @convention(c) (Int32) -> Void

    private static var image: UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: -2) }

    static func start(log: @escaping (String) -> Void) {
        guard let startSymbol = dlsym(image, "kh_sparkle_start") else {
            // No shim in this build (a harness compiles the app's sources alone).
            return
        }
        if let callbackSymbol = dlsym(image, "kh_sparkle_set_state_callback") {
            let setCallback = unsafeBitCast(callbackSymbol, to: SetCallback.self)
            setCallback { state in
                switch state {
                case 1: NSLog("Printer Studio: an update is being installed; new work waits")
                case 2: NSLog("Printer Studio: relaunching into the new version")
                default: NSLog("Printer Studio: no update in progress")
                }
            }
        }
        let rc = unsafeBitCast(startSymbol, to: Start.self)()
        guard rc != 0 else { return }
        var reason = "no reason given"
        if let errorSymbol = dlsym(image, "kh_sparkle_last_error"),
           let text = unsafeBitCast(errorSymbol, to: LastError.self)() {
            reason = String(cString: text)
        }
        NSLog("Printer Studio: self-update refused (%d): %@", rc, reason)
        log("Automatic updates are not running: \(reason)")
    }
}
