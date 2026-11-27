import Foundation

/// Proves the plain-words diagnosis for a shared queue that accepts jobs and
/// then waits: which cause is named, and which fix is offered.
@main
struct TestQueueHealth {
    static func printer(_ uri: String, reasons: [String], message: String = "") -> Printer {
        var value = Printer(name: "Q")
        value.deviceURI = uri
        value.isShared = true
        value.stateReasons = reasons
        value.stateMessage = message
        return value
    }

    static func main() {
        let usb = "usb://HP/Laser%20107a?serial=SN107AUSB"
        let network = "dnssd://HP%20Laser%20108w._ipp._tcp.local./?uuid=x"

        // What CUPS means by "offline".
        precondition(printer(usb, reasons: ["offline-report"]).isOffline,
                     "offline-report must read as offline")
        precondition(printer(usb, reasons: ["connecting-to-device", "offline-report"]).isOffline,
                     "connecting-to-device must read as offline")
        precondition(!printer(usb, reasons: []).isOffline, "no reasons must read as online")
        precondition(!printer(usb, reasons: [""]).isOffline, "an empty reason must read as online")

        // CUPS's own sentence, never blank.
        precondition(printer(usb, reasons: ["offline-report"]).offlineSummary == "The printer is offline.",
                     "an empty state message must fall back to a plain sentence")
        let said = printer(usb, reasons: ["offline-report"], message: "The printer is offline.")
        precondition(said.offlineSummary == "The printer is offline.", "CUPS's own words must be kept")

        func recovery(_ value: Printer, laser: Bool, held: Bool, auto: Bool) -> QueueHealth.Recovery {
            QueueHealth.recovery(printer: value, laserPresent: laser,
                                 heldByIPPUSB: held, automaticRelease: auto)
        }
        let offline = printer(usb, reasons: ["offline-report"], message: "The printer is offline.")

        precondition(recovery(offline, laser: false, held: false, auto: false) == .connectPrinter,
                     "no USB device present must ask for the cable")
        precondition(recovery(offline, laser: true, held: true, auto: true) == .releaseFromIPPUSB,
                     "ippusbd holding the device must offer the release")
        precondition(recovery(offline, laser: true, held: false, auto: false) == .keepReady,
                     "no automatic release must offer to keep it ready")
        precondition(recovery(offline, laser: true, held: false, auto: true) == .replug,
                     "everything in place and still offline must ask for a replug")
        precondition(recovery(printer(network, reasons: ["offline-report"]), laser: true, held: true, auto: true) == .checkNetwork,
                     "a network queue must ask about the network, not the USB cable")
        precondition(recovery(printer(usb, reasons: []), laser: true, held: true, auto: false) == .ready,
                     "a reachable queue must read as ready")

        precondition(QueueHealth.actionTitle(.releaseFromIPPUSB) == "Release it", "release action")
        precondition(QueueHealth.actionTitle(.keepReady) == "Keep it ready", "keep-ready action")
        precondition(QueueHealth.actionTitle(.connectPrinter) == nil, "a cable cannot be fixed by a button")
        precondition(QueueHealth.actionTitle(.checkNetwork) == nil, "a network cannot be fixed by a button")
        precondition(QueueHealth.actionTitle(.ready) == nil, "nothing to fix when ready")
        precondition(QueueHealth.needsAutomaticRelease(.keepReady), "keep-ready installs the release service")
        precondition(QueueHealth.needsAutomaticRelease(.releaseFromIPPUSB), "the release installs the service")
        precondition(!QueueHealth.needsAutomaticRelease(.checkNetwork), "no service change for a network queue")

        print("PASS: 19 checks — the offline cause and its fix are named, never guessed")
    }
}
