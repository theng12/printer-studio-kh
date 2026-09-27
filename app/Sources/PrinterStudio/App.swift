import SwiftUI
import AppKit

// MARK: - Entry point

@main
struct PrinterStudioApp: App {
    @StateObject private var state = AppState()

    /// The menu bar is home, so the window stays closed on a normal launch.
    /// It opens on the very first run (so the app is discoverable) and
    /// whenever `--show-window` is passed, which the build smoke test uses.
    ///
    /// Decided once, in `init`, and stored: reading the "first run" flag
    /// lazily would already have been overwritten by the time `body` ran.
    private let showWindowOnLaunch: Bool

    init() {
        let isFirstRun = !UserDefaults.standard.bool(forKey: "hasCompletedFirstRun")
        UserDefaults.standard.set(true, forKey: "hasCompletedFirstRun")
        showWindowOnLaunch = isFirstRun || CommandLine.arguments.contains("--show-window")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            Image(systemName: state.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)

        Window("Printer Studio KH", id: "main") {
            MainWindow()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 580)
        }
        .defaultLaunchBehavior(showWindowOnLaunch ? .presented : .suppressed)
    }
}

// MARK: - App state

final class AppState: ObservableObject {

    @Published var printers: [Printer] = []
    @Published var detailedPrinters: [Printer] = []
    @Published var sharingEnabled = false
    @Published var watcherInstalled = false
    @Published var watcherLoaded = false
    @Published var shareLog: [String] = []
    @Published var usbDevices: [USBDevice] = []
    @Published var unfinishedJobs: [String] = []
    @Published var activity: [LogEntry] = []

    @Published var busy = false
    @Published var busyMessage = ""
    @Published var lastError: String?

    /// Which sidebar screen is showing. This lives here rather than in a
    /// `@State` because SwiftUI's `@State` is a macro whose plugin is only
    /// shipped with full Xcode, and this app is built with Command Line Tools.
    @Published var screen: Screen? = .overview

    private let work = DispatchQueue(label: "com.theng12.printerstudio.work", qos: .userInitiated)

    init() {
        log("Printer Studio KH started.")
        refresh()
    }

    // MARK: Derived

    var laser107a: USBDevice? { usbDevices.first { $0.isLaser107a } }

    var queuesHeldShut: [Printer] { detailedPrinters.filter { $0.isHeldShut } }

    var problematicPrinters: [Printer] {
        printers.filter { $0.isStopped } + queuesHeldShut
    }

    var menuBarSymbol: String {
        if !queuesHeldShut.isEmpty { return "exclamationmark.triangle.fill" }
        if !unfinishedJobs.isEmpty { return "printer.fill" }
        if printers.contains(where: { $0.isPrinting }) { return "printer.fill" }
        return "printer"
    }

    var statusSummary: String {
        if !queuesHeldShut.isEmpty {
            return "\(queuesHeldShut.count) shared queue\(queuesHeldShut.count == 1 ? "" : "s") blocked"
        }
        if !unfinishedJobs.isEmpty {
            return "\(unfinishedJobs.count) job\(unfinishedJobs.count == 1 ? "" : "s") in progress"
        }
        return "\(printers.count) printer\(printers.count == 1 ? "" : "s")"
    }

    // MARK: Logging

    func log(_ message: String, kind: LogEntry.Kind = .info) {
        DispatchQueue.main.async {
            self.activity.insert(LogEntry(message, kind: kind), at: 0)
            if self.activity.count > 300 { self.activity.removeLast(self.activity.count - 300) }
        }
    }

    private func report(_ result: CommandResult, success: String) {
        if result.ok {
            log(success, kind: .success)
        } else if result.status == -128 {
            log("Cancelled.", kind: .warning)
        } else {
            log(result.combined.isEmpty ? "Command failed." : result.combined, kind: .error)
        }
    }

    // MARK: Refresh

    /// Cheap refresh — safe to run often and from the menu bar.
    func refresh() {
        work.async { [weak self] in
            guard let self else { return }
            let printers = CUPS.listPrinters()
            let sharing = CUPS.isSharingEnabled()
            let usb = Driver.usbDevices()
            let jobs = CUPS.unfinishedJobs()
            let installed = ShareFix.isWatcherInstalled
            let loaded = ShareFix.isWatcherLoaded

            DispatchQueue.main.async {
                self.printers = printers
                self.sharingEnabled = sharing
                self.usbDevices = usb
                self.unfinishedJobs = jobs
                self.watcherInstalled = installed
                self.watcherLoaded = loaded
                // Keep the detailed list in step for queues that no longer exist.
                let names = Set(printers.map(\.name))
                self.detailedPrinters.removeAll { !names.contains($0.name) }
            }

            // The detailed pass is the slow one; only do it when needed.
            let detailed = CUPS.detailedPrinters()
            let logLines = ShareFix.recentLogLines()
            DispatchQueue.main.async {
                self.detailedPrinters = detailed
                self.shareLog = logLines
            }
        }
    }

    /// Runs a shell action off the main thread, then refreshes.
    private func perform(_ message: String, _ body: @escaping () -> CommandResult, success: String) {
        busy = true
        busyMessage = message
        log(message)
        work.async { [weak self] in
            guard let self else { return }
            let result = body()
            DispatchQueue.main.async {
                self.busy = false
                self.busyMessage = ""
                self.report(result, success: success)
                self.refresh()
            }
        }
    }

    // MARK: Actions

    func fixSharingNow() {
        perform("Opening shared queues to the LAN…", { ShareFix.fixNow() },
                success: "Shared queues re-opened to the LAN.")
    }

    func installWatcher() {
        perform("Installing the background watcher…", { ShareFix.installWatcher() },
                success: "Background watcher installed — shared queues stay open automatically.")
    }

    func removeWatcher() {
        perform("Removing the background watcher…", { ShareFix.uninstallWatcher() },
                success: "Background watcher removed.")
    }

    func setSharing(_ enabled: Bool) {
        perform(
            enabled ? "Turning on Printer Sharing…" : "Turning off Printer Sharing…",
            { CUPS.setSharingEnabled(enabled) },
            success: enabled ? "Printer Sharing is on." : "Printer Sharing is off."
        )
    }

    func openQueue(_ printer: Printer) {
        perform("Opening \(printer.name) to all users…",
                { CUPS.allowAllUsers(printer.name) },
                success: "\(printer.name) is now open to all users.")
    }

    func restrictQueue(_ printer: Printer) {
        perform("Restoring the restricted ACL on \(printer.name)…",
                { CUPS.restrictToUserACL(printer.name) },
                success: "\(printer.name) is restricted again.")
    }

    func toggleShared(_ printer: Printer) {
        let target = !printer.isShared
        perform(target ? "Sharing \(printer.name)…" : "Stopping sharing of \(printer.name)…",
                { CUPS.setShared(printer.name, target) },
                success: target ? "\(printer.name) is shared." : "\(printer.name) is no longer shared.")
    }

    func toggleEnabled(_ printer: Printer) {
        let target = !printer.enabled
        perform(target ? "Enabling \(printer.name)…" : "Pausing \(printer.name)…",
                { CUPS.setEnabled(printer.name, target) },
                success: target ? "\(printer.name) is enabled." : "\(printer.name) is paused.")
    }

    func testPrint(_ printer: Printer) {
        perform("Sending a test page to \(printer.name)…",
                { CUPS.printTestPage(printer.name) },
                success: "Test page sent to \(printer.name).")
    }

    func clearJobs(on printer: Printer) {
        perform("Clearing jobs on \(printer.name)…",
                { CUPS.cancelAllJobs(on: printer.name) },
                success: "Jobs cleared on \(printer.name).")
    }

    func installDriver() {
        guard DriverInstaller.hasPayload else {
            log("This build is missing the bundled driver files.", kind: .error)
            return
        }
        guard let uri = DriverInstaller.usbDeviceURI() else {
            log("No USB printer was found. Plug the HP Laser 107a in, switch it on, then try again.",
                kind: .warning)
            return
        }
        log("Found printer at \(uri)")
        perform("Installing the printer driver…",
                { DriverInstaller.install(deviceURI: uri) },
                success: "Driver installed. The HP Laser 107a is set up and shared on your network.")
    }

    func uninstallDriver() {
        perform("Removing the printer driver…",
                { DriverInstaller.uninstall() },
                success: "The printer driver and queue were removed.")
    }

    func refreshNow() {
        log("Refreshing…")
        refresh()
    }

    /// Opens the instructions that ship inside the app, so the app can be sent
    /// on its own without a separate Read Me.
    func openReadMe() {
        guard let url = Bundle.main.url(forResource: "Read Me First", withExtension: "txt") else {
            log("The bundled Read Me could not be found.", kind: .warning)
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Menu bar

struct MenuBarContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(state.statusSummary)

        Divider()

        Button("Open Printer Studio KH…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .keyboardShortcut("o")

        Button("Fix shared queues now") { state.fixSharingNow() }
        Button("Refresh") { state.refreshNow() }
        Button("Read Me First…") { state.openReadMe() }

        if state.busy {
            Divider()
            Text(state.busyMessage)
        }

        Divider()

        Button("Quit Printer Studio KH") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
