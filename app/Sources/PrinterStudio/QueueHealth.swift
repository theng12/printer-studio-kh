import Foundation

/// Why a shared queue is not printing, in plain words, and the one action that
/// can fix it. Kept out of the views so it can be tested without a window: when
/// AirPrint "fails", the last step — the print — is what is stuck, because the
/// queue is offline and the installer's retry policy keeps the job waiting
/// instead of failing it. The screens must name that cause.
enum QueueHealth {
    enum Recovery: Equatable {
        case ready
        case connectPrinter
        case checkNetwork
        case releaseFromIPPUSB
        case keepReady
        case replug
    }

    static func recovery(printer: Printer, laserPresent: Bool, heldByIPPUSB: Bool,
                         automaticRelease: Bool) -> Recovery {
        guard printer.isOffline else { return .ready }
        if printer.transport != .usb { return .checkNetwork }
        if !laserPresent { return .connectPrinter }
        if heldByIPPUSB { return .releaseFromIPPUSB }
        if !automaticRelease { return .keepReady }
        return .replug
    }

    static func title(_ recovery: Recovery) -> String {
        switch recovery {
        case .ready: return "Ready"
        case .connectPrinter: return "The printer is not connected"
        case .checkNetwork: return "The printer is not answering"
        case .releaseFromIPPUSB: return "macOS is holding the printer"
        case .keepReady: return "The printer can be taken again"
        case .replug: return "The printer stopped answering"
        }
    }

    static func detail(_ recovery: Recovery) -> String {
        switch recovery {
        case .ready:
            return "Jobs print normally."
        case .connectPrinter:
            return "Connect its USB cable and switch it on. Jobs already sent wait until it is back."
        case .checkNetwork:
            return "Check that it is switched on and on the same network. Jobs already sent wait until it answers."
        case .releaseFromIPPUSB:
            return "macOS's own USB service has taken the printer, so the queue is offline and nothing prints. Release it once — it stays released after restarts."
        case .keepReady:
            return "Jobs only print while nothing else claims the USB printer. Turn on automatic release so it stays ready after a restart or a replug."
        case .replug:
            return "Unplug the USB cable and plug it back in. If it stays offline, check that the printer is switched on."
        }
    }

    /// The button that fixes it, or nil when only the person can (a cable).
    static func actionTitle(_ recovery: Recovery) -> String? {
        switch recovery {
        case .ready, .connectPrinter, .checkNetwork, .replug: return nil
        case .releaseFromIPPUSB: return "Release it"
        case .keepReady: return "Keep it ready"
        }
    }

    static func needsAutomaticRelease(_ recovery: Recovery) -> Bool {
        recovery == .releaseFromIPPUSB || recovery == .keepReady
    }
}
