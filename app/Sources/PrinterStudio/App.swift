import SwiftUI
import AppKit
import AVFoundation

// MARK: - Entry point

/// Opens the main window once at launch. A menu-bar app gets no window for
/// free, and the rule is that launching shows it; `PRINTER_STUDIO_NO_WINDOW`
/// keeps a hidden or packaged test run from putting anything on screen.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    let symbol: String

    private var hiddenRun: Bool {
        ProcessInfo.processInfo.environment["PRINTER_STUDIO_NO_WINDOW"] == "1"
            || ProcessInfo.processInfo.environment["PRINTER_STUDIO_AIRPRINT_TEST"] == "1"
            || ProcessInfo.processInfo.environment["PRINTER_STUDIO_SIGNING_SMOKE"] != nil
    }

    var body: some View {
        Image(systemName: symbol)
            .onAppear {
                guard !hiddenRun else { return }
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
            }
    }
}

/// The application menu can open or rebuild the window even after it is closed.
struct MainCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button("Quit Printer Studio KH") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        CommandGroup(after: .appInfo) {
            Button("Open Printer Studio KH") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("o")
        }
    }
}

@main
struct PrinterStudioApp: App {
    @StateObject private var state = AppState()
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

    init() {
        // Before the first window exists, so it opens already in the chosen
        // scheme. The stored choice owns the real AppKit appearance; SwiftUI's
        // colour scheme alone left the cards and the page disagreeing.
        Appearance.apply(.stored(UserDefaults.standard.string(forKey: "appearance")))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            MenuBarLabel(symbol: state.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)

        // The window opens at launch on every supported version.
        //
        // macOS 15 added `defaultLaunchBehavior`, which would let it stay shut
        // until asked for. It cannot be used here: SwiftUI has no type-erased
        // Scene and `SceneBuilder` does not accept `if #available`, so the
        // modifier cannot be applied conditionally, and applying it
        // unconditionally would raise the deployment target to 15 and lock out
        // older Macs. Showing the window is the predictable option, and the
        // menu bar icon stays put either way.
        Window("Printer Studio KH", id: "main") {
            MainWindow()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 580)
                // Every window inherits the app appearance, so one change here
                // repaints the window, its sidebar and every page.
                .onChange(of: appearanceRaw) { Appearance.apply(.stored($0)) }
        }
        .commands { MainCommands() }

        Window("What's New", id: "whats-new") {
            WhatsNewView()
        }
        .defaultSize(width: 520, height: 300)
        .windowResizability(.contentMinSize)

        Window("Support Printer Studio KH", id: "support") {
            SupportView()
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - App state

final class AppState: ObservableObject {

    @Published var printers: [Printer] = []
    /// Set when CUPS could not be read; the list is unknown, not empty.
    @Published var printersError: String?
    @Published var detailedPrinters: [Printer] = []
    @Published var sharingEnabled = false
    @Published var watcherInstalled = false
    @Published var watcherLoaded = false
    @Published var shareLog: [String] = []
    @Published var usbDevices: [USBDevice] = []
    /// True when Apple's IPP-over-USB daemon is holding the printer, which makes
    /// the queue report "offline" for ever. See Driver.ippusbdHoldingPrinter().
    @Published var printerHeldByIPPUSB = false
    /// True when the AirPrint advertisement for iOS is installed.
    @Published var airPrintInstalled = false
    @Published var labelPrintingNeedsSetup = false
    /// True when the app is registered to open at login.
    @Published var startsAtLogin = false
    @Published var automaticUSBRelease = false

    /// The user's sticker sizes, as last saved.
    @Published var stickerSizes: [StickerSize] = ProcessInfo.processInfo.environment["PRINTER_STUDIO_SIGNING_SMOKE"] == nil ? StickerSizeStore.load() : []
    /// Every CUPS queue, flagged where it looks like a label printer.
    @Published var labelQueues: [(queue: String, isLabel: Bool)] = []
    /// What each label queue currently advertises, straight from the PPD —
    /// the same list an iPhone reads. Lets the screen answer "did it work?"
    /// without needing the phone.
    @Published var offeredSizes: [String: [String]] = [:]
    @Published var printerNameDrafts: [String: String] = [:]
    @Published var paperChoices: [String: [PageSizeInstaller.PaperChoice]] = [:]
    @Published var selectedPaper: [String: String] = [:]
    @Published var unfinishedJobs: [String] = []
    @Published var activity: [LogEntry] = []

    @Published var busy = false
    @Published var busyMessage = ""
    /// The last action's result, shown on the page where it happened until dismissed.
    @Published var lastMessage: String?
    @Published var lastMessageOK = true
    @Published var reportFeedback: String?

    /// Off unless the person turns it on: a chime and a line the moment a job
    /// lands in the queue, so a phone print is acknowledged in about a second
    /// instead of waiting out the printer's warm-up in silence. The voice is
    /// separate, and defaults to the plain chime.
    @Published var notifyOnJobReceived = UserDefaults.standard.bool(forKey: "notifyOnJobReceived") {
        didSet {
            UserDefaults.standard.set(notifyOnJobReceived, forKey: "notifyOnJobReceived")
            updateJobWatch()
        }
    }
    @Published var announcementVoice = VoiceClip.stored(UserDefaults.standard.string(forKey: "announcementVoice")) {
        didSet { UserDefaults.standard.set(announcementVoice.rawValue, forKey: "announcementVoice") }
    }
    private var announcer: AVAudioPlayer?
    private var jobWatchTimer: Timer?
    private var seenJobIDs: Set<String> = []
    private var jobWatchFirstLook = true
    private var jobWatchReadFailed = false

    /// Which sidebar screen is showing. This lives here rather than in a
    /// `@State` because SwiftUI's `@State` is a macro whose plugin is only
    /// shipped with full Xcode, and this app is built with Command Line Tools.
    @Published var screen: Screen? = .overview

    private let work = DispatchQueue(label: "com.theng12.printerstudio.work", qos: .userInitiated)

    init() {
        // Packaged launch tests must not touch login items, preferences or printer services.
        if let receipt = ProcessInfo.processInfo.environment["PRINTER_STUDIO_SIGNING_SMOKE"] {
            DispatchQueue.main.async {
                do {
                    let data = try JSONSerialization.data(withJSONObject: [
                        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                        "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
                        "pid": ProcessInfo.processInfo.processIdentifier,
                        "ready": true,
                    ])
                    try data.write(to: URL(fileURLWithPath: receipt), options: .atomic)
                } catch {
                    fputs("Signing launch test could not write its receipt: \(error)\n", stderr)
                    exit(1)
                }
            }
            return
        }
        log("Printer Studio KH started.")
        DispatchQueue.main.async { self.updateJobWatch() }

        // When launchd starts us at login we should leave only the menu bar
        // icon. The window scene always opens one, and macOS 13 and 14 have no
        // way to suppress that declaratively — `defaultLaunchBehavior` is
        // macOS 15 and cannot be applied conditionally, because SwiftUI has no
        // type-erased Scene. So close it as soon as it exists.
        if CommandLine.arguments.contains("--background") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                for window in NSApp.windows where window.title == "Printer Studio KH" {
                    window.close()
                }
            }
        }

        // Enable on first launch, then respect the Settings switch. Refresh an
        // enabled item after an app move so launchd keeps the current path.
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") || LoginItem.isEnabled {
            let result = LoginItem.enable()
            report(result, success: "Printer Studio KH will open at login.", action: "Turning on start at login")
            if result.ok { UserDefaults.standard.set(true, forKey: "loginItemConfigured") }
        }
        work.async {
            let result = DriverInstaller.refreshAirPrintBridgeIfOutdated()
            if !result.ok { self.report(result, success: "", action: "Refreshing the AirPrint bridge") }
            // Upgrades an older shell-based watcher without an admin prompt.
            let watcher = ShareFix.migrateWatcherIfNeeded()
            if !watcher.ok { self.report(watcher, success: "", action: "Upgrading the background watcher") }
            DispatchQueue.main.async { self.refresh() }
        }
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

    // MARK: Job watch

    /// Says so out loud with the chosen clip, or the plain chime when the person
    /// picked "Sound only" or a recording that is no longer there. A clip that
    /// will not load falls back out loud: the card still says the voice is in
    /// use, so silence here would be a lie.
    private func announce() {
        if let url = announcementVoice.url {
            if let player = try? AVAudioPlayer(contentsOf: url) {
                announcer = player
                player.prepareToPlay()
                player.play()
                return
            }
            log("Could not play the \(announcementVoice.title) announcement at \(url.lastPathComponent); used the plain chime instead.",
                kind: .warning)
        }
        NSSound(named: NSSound.Name(VoiceClip.chimeName))?.play()
    }

    /// Runs only while the switch is on, so an app nobody asked to be noisy
    /// spends nothing. Two seconds is fast enough to beat the printer's own
    /// warm-up and cheap enough to run all day. The queue is read off the main
    /// thread: a wedged cupsd must never freeze the window.
    func updateJobWatch() {
        jobWatchTimer?.invalidate()
        jobWatchTimer = nil
        guard notifyOnJobReceived else { return }
        jobWatchFirstLook = true
        jobWatchReadFailed = false
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.busy else { return }
            self.work.async {
                let read = CUPS.unfinishedJobsRead()
                DispatchQueue.main.async {
                    guard let jobs = read.jobs else {
                        // A read that failed says nothing about what is queued.
                        // Keep what we knew and say why, once.
                        if !self.jobWatchReadFailed {
                            self.jobWatchReadFailed = true
                            self.log("Could not read the print queue: \(read.error ?? "no reason given")",
                                     kind: .warning)
                        }
                        return
                    }
                    self.jobWatchReadFailed = false
                    let fresh = JobWatch.newIDs(previous: self.seenJobIDs, current: jobs,
                                                firstLook: self.jobWatchFirstLook)
                    self.seenJobIDs = JobWatch.ids(jobs)
                    self.jobWatchFirstLook = false
                    // The same read feeds the page, so the count on screen and the
                    // chime can never disagree.
                    self.unfinishedJobs = jobs
                    guard !fresh.isEmpty else { return }
                    self.announce()
                    self.log("Received \(fresh.joined(separator: ", ")).", kind: .success)
                    // "Received", never "printing": the queue being stopped, held
                    // or backed up is a state this app shows elsewhere and cannot
                    // rule out from an lpstat line.
                    self.lastMessage = fresh.count == 1
                        ? "Job received."
                        : "\(fresh.count) jobs received."
                    self.lastMessageOK = true
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        jobWatchTimer = timer
    }

    // MARK: Logging

    func log(_ message: String, kind: LogEntry.Kind = .info) {
        DispatchQueue.main.async {
            self.activity.insert(LogEntry(message, kind: kind), at: 0)
            if self.activity.count > 300 { self.activity.removeLast(self.activity.count - 300) }
        }
    }

    private func report(_ result: CommandResult, success: String, action: String) {
        let outcome = OutcomeMessage.outcome(for: result, success: success, action: action)
        log(outcome.message, kind: outcome.kind)
        DispatchQueue.main.async {
            self.lastMessage = outcome.message
            self.lastMessageOK = outcome.ok
        }
    }

    // MARK: Refresh

    /// Cheap refresh — safe to run often and from the menu bar.
    func refresh(announce: Bool = false) {
        work.async { [weak self] in
            guard let self else { return }
            let listing = CUPS.listPrintersChecked()
            let printers = listing.printers
            let sharing = CUPS.isSharingEnabled()
            let usb = Driver.usbDevices()
            let jobs = CUPS.unfinishedJobs()
            let installed = ShareFix.isWatcherInstalled
            let loaded = ShareFix.isWatcherLoaded
            let held = Driver.ippusbdHoldingPrinter()
            let airPrint = DriverInstaller.isAirPrintInstalled
            let labelSetup = LabelPrintFilter.needsSetup(printers: printers)
            let login = LoginItem.isEnabled
            let automaticUSB = USBPrinterService.isInstalled && USBPrinterService.isLoaded
            let labelQueues = PageSizeInstaller.queues()
            var offered: [String: [String]] = [:]
            var choices: [String: [PageSizeInstaller.PaperChoice]] = [:]
            var selected: [String: String] = [:]
            for printer in printers {
                choices[printer.name] = PageSizeInstaller.choices(queue: printer.name)
                selected[printer.name] = PageSizeInstaller.defaultKey(queue: printer.name)
            }
            for entry in labelQueues where entry.isLabel {
                offered[entry.queue] = PageSizeInstaller.currentSizes(queue: entry.queue)
            }

            DispatchQueue.main.async {
                self.printers = printers
                self.printersError = listing.error
                self.sharingEnabled = sharing
                self.usbDevices = usb
                self.unfinishedJobs = jobs
                self.watcherInstalled = installed
                self.watcherLoaded = loaded
                self.printerHeldByIPPUSB = held
                self.airPrintInstalled = airPrint
                self.labelPrintingNeedsSetup = labelSetup
                self.startsAtLogin = login
                self.automaticUSBRelease = automaticUSB
                self.labelQueues = labelQueues
                self.offeredSizes = offered
                self.paperChoices = choices
                self.selectedPaper = selected
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
                if announce {
                    self.log("Refreshed — \(self.printers.count) printer\(self.printers.count == 1 ? "" : "s"), printer sharing \(self.sharingEnabled ? "on" : "off").",
                             kind: .success)
                }
            }
        }
    }

    /// The offscreen render harness (PRINTER_STUDIO_RENDER) drives real controls
    /// through their real actions. Only the command itself is faked, and the
    /// system read-back is skipped so the harness's fixture state stays put; the
    /// busy state, banner and activity row all still run.
    var renderActionsStubbed: Bool {
        ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER"] == "1"
    }

    /// Runs a shell action off the main thread, then refreshes.
    private func perform(_ message: String, _ body: @escaping () -> CommandResult, success: String) {
        busy = true
        busyMessage = message
        log(message)
        work.async { [weak self] in
            guard let self else { return }
            let result = self.renderActionsStubbed ? CommandResult(status: 0, stdout: "", stderr: "") : body()
            DispatchQueue.main.async {
                self.busy = false
                self.busyMessage = ""
                self.report(result, success: success,
                            action: OutcomeMessage.actionLabel(message))
                if !self.renderActionsStubbed {
                    self.refresh()
                } else {
                    // Show the state the success implies, so the harness's
                    // after-image is the terminal state, not the old one.
                    RenderFixtures.apply(success: success, to: self)
                }
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
        perform("Opening \(printer.displayName) to all users…",
                { CUPS.allowAllUsers(printer.name) },
                success: "\(printer.displayName) is now open to all users.")
    }

    func restrictQueue(_ printer: Printer) {
        perform("Restoring the restricted ACL on \(printer.displayName)…",
                { CUPS.restrictToUserACL(printer.name) },
                success: "\(printer.displayName) is restricted again.")
    }

    func toggleShared(_ printer: Printer) {
        let target = !printer.isShared
        perform(target ? "Sharing \(printer.displayName)…" : "Stopping sharing of \(printer.displayName)…",
                { CUPS.setShared(printer.name, target) },
                success: target ? "\(printer.displayName) is shared." : "\(printer.displayName) is no longer shared.")
    }

    func toggleEnabled(_ printer: Printer) {
        let target = !printer.enabled
        perform(target ? "Enabling \(printer.displayName)…" : "Pausing \(printer.displayName)…",
                { CUPS.setEnabled(printer.name, target) },
                success: target ? "\(printer.displayName) is enabled." : "\(printer.displayName) is paused.")
    }

    func renamePrinter(_ printer: Printer) {
        let name = printerNameDrafts[printer.name] ?? printer.displayName
        perform("Saving printer name…", { CUPS.rename(printer.name, to: name) },
                success: "Printer name saved. Reopen the print dialog to see it.")
    }

    func selectPaper(_ key: String, for printer: Printer) {
        perform("Setting paper size for \(printer.displayName)…",
                { PageSizeInstaller.setDefault(queue: printer.name, key: key) },
                success: "Paper size saved for Mac and AirPrint. Reopen the print dialog and select this size.")
    }

    func testPrint(_ printer: Printer) {
        perform("Sending one test page to \(printer.displayName)…",
                { CUPS.printTestPage(printer.name) },
                success: "Test page sent to \(printer.displayName).")
    }

    func clearJobs(on printer: Printer) {
        perform("Clearing jobs on \(printer.displayName)…",
                { CUPS.cancelAllJobs(on: printer.name) },
                success: "Jobs cleared on \(printer.displayName).")
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

    func releasePrinter() {
        perform("Releasing the printer from macOS's IPP-over-USB service…",
                { DriverInstaller.releasePrinter() },
                success: "Automatic USB release is running — the printer is checked every 15 seconds.")
    }

    func setupLabelPrinting() {
        perform("Setting up iPhone label printing…", {
            let result = LabelPrintFilter.installIfNeeded()
            guard result.ok else { return result }
            return DriverInstaller.installAirPrintBridge()
        }, success: "Label printing setup is complete. iPhone output is not checked — test one label from your phone.")
    }

    func installAirPrint() {
        perform("Turning on Printer Sharing and AirPrint…",
                { DriverInstaller.installAirPrintBridge() },
                success: "Printer Sharing and AirPrint are enabled. Reopen the print dialog on your iPhone or iPad.")
    }

    func removeAirPrint() {
        perform("Stopping the AirPrint advertisement…",
                { DriverInstaller.removeAirPrintBridge() },
                success: "AirPrint advertisement stopped.")
    }

    // MARK: - Sticker sizes

    func saveStickerSizes() {
        StickerSizeStore.save(stickerSizes)
    }

    func addStickerSize() {
        stickerSizes.append(StickerSize(name: "New size", widthMM: 50, heightMM: 30))
        StickerSizeStore.save(stickerSizes)
    }

    func removeStickerSize(_ id: UUID) {
        stickerSizes.removeAll { $0.id == id }
        StickerSizeStore.save(stickerSizes)
    }

    func resetStickerSizes() {
        stickerSizes = StickerSizeStore.defaults
        StickerSizeStore.save(stickerSizes)
    }

    /// Writes the sizes into every queue that looks like a label printer, which
    /// is what makes them appear on an iPhone.
    func applyStickerSizes() {
        StickerSizeStore.save(stickerSizes)
        let targets = labelQueues.filter(\.isLabel).map(\.queue)
        // Copied out first: the closure is @escaping, so it needs its own value
        // rather than a reference to the published property.
        let sizes = stickerSizes
        perform("Adding your sizes to \(targets.count) printer\(targets.count == 1 ? "" : "s")…",
                {
                    let result = PageSizeInstaller.apply(sizes: sizes, to: targets)
                    if result.ok { self.log(result.combined) }
                    return result
                },
                success: "Sizes checked and applied. See Activity for each printer’s results, then reopen your print dialog.")
    }

    func setAutomaticUSBRelease(_ enabled: Bool) {
        perform(enabled ? "Keeping the USB printer ready after restarts…" : "Turning off automatic USB release…",
                { enabled ? USBPrinterService.enable() : USBPrinterService.disable() },
                success: enabled ? "Automatic USB release is on." : "Automatic USB release is off.")
    }

    func setStartAtLogin(_ enabled: Bool) {
        let result = renderActionsStubbed
            ? CommandResult(status: 0, stdout: "", stderr: "")
            : (enabled ? LoginItem.enable() : LoginItem.disable())
        if result.ok { UserDefaults.standard.set(true, forKey: "loginItemConfigured") }
        report(result, success: enabled
               ? "Printer Studio KH will open at login."
               : "Printer Studio KH will no longer open at login.",
               action: enabled ? "Turning on start at login" : "Turning off start at login")
        if !renderActionsStubbed { refresh() }
    }

    func refreshNow() {
        log("Refreshing…")
        refresh(announce: true)
    }

    /// Takes the app back off this Mac and then quits, so nothing it installed is
    /// left behind. Settings and saved sizes are the person's, and stay.
    func removeEverything() {
        let result = Removal.everything()
        log(result.combined, kind: result.ok ? .info : .warning)
        reportFeedback = result.ok ? "Removed from this Mac. Your settings were kept." : result.combined
        refresh()
        if result.ok {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
        }
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

    /// Generates a diagnostic error report off the main thread and copies it
    /// to the macOS clipboard.
    func copyErrorReport() {
        let snapshot = activity
        reportFeedback = "Generating…"
        work.async { [weak self] in
            guard let self else { return }
            let report = DiagnosticReport.generate(activitySnapshot: snapshot)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                NSPasteboard.general.clearContents()
                let ok = NSPasteboard.general.setString(report, forType: .string)
                if ok {
                    self.log("Diagnostic error report copied to clipboard.", kind: .success)
                    self.reportFeedback = "Copied to clipboard"
                } else {
                    self.log("Failed to copy error report to clipboard.", kind: .error)
                    self.reportFeedback = "Failed to copy"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    if self?.reportFeedback == "Copied to clipboard" {
                        self?.reportFeedback = nil
                    }
                }
            }
        }
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

        Text("Printer Studio KH \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")")
            .foregroundStyle(.secondary)
            .disabled(true)

        Button("Quit Printer Studio KH") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
