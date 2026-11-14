import Foundation

// Render-harness only. The offscreen interaction pass stubs the system command
// (AppState.perform) and normally skips the real read-back refresh; without the
// read-back the after-image would contradict the banner. This applies the state
// change a given success message implies so the evidence shows the terminal
// state. Never reached when PRINTER_STUDIO_RENDER is unset.

enum RenderFixtures {
    static func apply(success: String, to state: AppState) {
        switch success {
        case "Background watcher removed.":
            state.watcherInstalled = false
            state.watcherLoaded = false
        case "Background watcher installed — shared queues stay open automatically.":
            state.watcherInstalled = true
            state.watcherLoaded = true
        case "Shared queues re-opened to the LAN.":
            state.detailedPrinters = state.detailedPrinters.map { printer in
                Printer(name: printer.name, description: printer.description, state: printer.state,
                        enabled: printer.enabled, accepting: printer.accepting,
                        deviceURI: printer.deviceURI, makeAndModel: printer.makeAndModel,
                        isShared: printer.isShared, hasUserACL: false)
            }
        case "Automatic USB release is running — the printer is checked every 15 seconds.":
            state.automaticUSBRelease = true
        case "Printer Studio KH will open at login.":
            state.startsAtLogin = true
        case "Printer Studio KH will no longer open at login.":
            state.startsAtLogin = false
        default:
            break
        }
    }
}
