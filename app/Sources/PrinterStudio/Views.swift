import SwiftUI
import AppKit

// MARK: - Main window

/// Sidebar destinations.
///
/// Declared at file scope rather than inside the view because the current
/// selection lives in AppState: `@State` is a SwiftUI *macro* whose plugin
/// ships only with full Xcode, so this app avoids it entirely and keeps view
/// state in the observable model instead.
enum Screen: String, CaseIterable, Identifiable {
    case overview, printers, sharing, stickers, setup, activity, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .printers: return "Printers"
        case .sharing: return "Sharing"
        case .stickers: return "Sticker Sizes"
        case .setup: return "HP Laser 107a"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.medium"
        case .printers: return "printer"
        case .sharing: return "wifi"
        case .stickers: return "tag"
        case .setup: return "wrench.and.screwdriver"
        case .activity: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.screen) {
                ForEach(Screen.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if state.busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(state.busyMessage).font(.caption).lineLimit(2)
                        }
                    }
                    Text(state.statusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.bar)
            }
        } detail: {
            Group {
                switch state.screen ?? .overview {
                case .overview: OverviewView()
                case .printers: PrintersView()
                case .sharing: SharingView()
                case .setup: SetupView()
                case .activity: ActivityView()
                case .stickers: StickerSizesView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.refreshNow()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(state.busy)
            }
        }
    }
}

/// A stand-in for `ContentUnavailableView`, which requires macOS 14.
/// Declared here so the app's deployment target can stay at macOS 13.
struct EmptyState: View {
    let title: String
    let symbol: String
    var detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Reusable pieces

struct StatusCard: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct AdviceRow: View {
    let symbol: String
    let tint: Color
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action).controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.08)))
    }
}

// MARK: - Overview

struct OverviewView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Printer Studio KH").font(.largeTitle.weight(.semibold))
                    Text("Share this Mac's printers with every device on your network — and keep them working.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    StatusCard(
                        title: "PRINTER SHARING",
                        value: state.sharingEnabled ? "On" : "Off",
                        symbol: state.sharingEnabled ? "checkmark.circle.fill" : "xmark.circle",
                        tint: state.sharingEnabled ? .green : .orange)
                    StatusCard(
                        title: "PRINTERS",
                        value: "\(state.printers.count)",
                        symbol: "printer")
                    StatusCard(
                        title: "QUEUES BLOCKED",
                        value: "\(state.queuesHeldShut.count)",
                        symbol: state.queuesHeldShut.isEmpty ? "checkmark.shield" : "exclamationmark.triangle.fill",
                        tint: state.queuesHeldShut.isEmpty ? .green : .red)
                    StatusCard(
                        title: "HP LASER 107a",
                        value: state.laser107a != nil ? "Connected" : "Not connected",
                        symbol: state.laser107a != nil ? "cable.connector" : "cable.connector.slash",
                        tint: state.laser107a != nil ? .green : .secondary)
                }

                if !advice.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What needs doing").font(.headline)
                        ForEach(Array(advice.enumerated()), id: \.offset) { _, item in
                            AdviceRow(symbol: item.symbol, tint: item.tint, text: item.text,
                                      actionTitle: item.actionTitle, action: item.action)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick actions").font(.headline)
                    HStack(spacing: 10) {
                        Button("Fix shared queues now") { state.fixSharingNow() }
                        Button(state.sharingEnabled ? "Turn off Printer Sharing" : "Turn on Printer Sharing") {
                            state.setSharing(!state.sharingEnabled)
                        }
                        Button("Refresh") { state.refreshNow() }
                        Button("Read Me First") { state.openReadMe() }
                            .help("Instructions that travel with the app, including how to open it on a Mac that received it over AirDrop or Telegram.")
                    }
                    .disabled(state.busy)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private struct Advice {
        let symbol: String
        let tint: Color
        let text: String
        var actionTitle: String?
        var action: (() -> Void)?
    }

    private var advice: [Advice] {
        var items: [Advice] = []

        if state.printerHeldByIPPUSB {
            items.append(Advice(
                symbol: "exclamationmark.triangle.fill", tint: .red,
                text: "macOS's IPP-over-USB service has claimed the printer. While it holds the device, CUPS cannot open it: the queue reports “offline” and jobs never print, with nothing logged to explain why. This comes back after a reboot or a replug.",
                actionTitle: "Release",
                action: { state.releasePrinter() }))
        }

        if !state.sharingEnabled {
            items.append(Advice(
                symbol: "wifi.slash", tint: .orange,
                text: "Printer Sharing is off, so other devices on your network cannot see this Mac's printers.",
                actionTitle: "Turn on",
                action: { state.setSharing(true) }))
        }

        if !state.queuesHeldShut.isEmpty {
            let names = state.queuesHeldShut.map(\.name).joined(separator: ", ")
            items.append(Advice(
                symbol: "lock.fill", tint: .red,
                text: "\(names) \(state.queuesHeldShut.count == 1 ? "is" : "are") shared but locked to specific users. Other Macs will report “Job held for authentication”.",
                actionTitle: "Fix now",
                action: { state.fixSharingNow() }))
        }

        if state.sharingEnabled && !state.watcherInstalled {
            items.append(Advice(
                symbol: "clock.arrow.circlepath", tint: .blue,
                text: "The background watcher is not installed. Without it, re-saving the Sharing settings can lock the queues again.",
                actionTitle: "Install",
                action: { state.installWatcher() }))
        }

        if state.laser107a == nil {
            items.append(Advice(
                symbol: "cable.connector", tint: .secondary,
                text: "The HP Laser 107a is not plugged in. Connect it by USB and it will appear here automatically."))
        } else if !Driver.isReady {
            items.append(Advice(
                symbol: "shippingbox", tint: .orange,
                text: "The HP Laser 107a is connected but its print driver is not installed yet. Open the “HP Laser 107a” tab."))
        }

        return items
    }
}

// MARK: - Printers

struct PrintersView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Printers on this Mac").font(.title2.weight(.semibold))

                if state.printers.isEmpty {
                    EmptyState(title: "No printers", symbol: "printer.slash",
                               detail: "This Mac has no print queues yet.")
                        .frame(height: 240)
                } else {
                    ForEach(state.printers) { printer in
                        PrinterCard(printer: printer)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct PrinterCard: View {
    @EnvironmentObject var state: AppState
    let printer: Printer

    private var detail: Printer? {
        state.detailedPrinters.first { $0.name == printer.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: printer.isStopped ? "printer.fill" : "printer")
                    .foregroundStyle(printer.isStopped ? .orange : .accentColor)
                Text(printer.name).font(.headline)
                Spacer()
                StateBadge(printer: printer)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Connection").foregroundStyle(.secondary)
                    Label(printer.friendlyLocation, systemImage: printer.transport.symbol)
                }
                if let model = detail?.makeAndModel ?? (printer.makeAndModel.isEmpty ? nil : printer.makeAndModel) {
                    GridRow {
                        Text("Model").foregroundStyle(.secondary)
                        Text(model)
                    }
                }
                GridRow {
                    Text("Shared").foregroundStyle(.secondary)
                    Text((detail?.isShared ?? printer.isShared) ? "Yes" : "No")
                }
                if let detail, detail.isShared {
                    GridRow {
                        Text("Access").foregroundStyle(.secondary)
                        if detail.hasUserACL {
                            Label("Locked to specific users", systemImage: "lock.fill").foregroundStyle(.red)
                        } else {
                            Label("Open to everyone", systemImage: "lock.open.fill").foregroundStyle(.green)
                        }
                    }
                }
            }
            .font(.callout)

            HStack(spacing: 8) {
                Button("Print test page") { state.testPrint(printer) }
                Button((detail?.isShared ?? printer.isShared) ? "Stop sharing" : "Share") {
                    state.toggleShared(detail ?? printer)
                }
                if let detail, detail.isHeldShut {
                    Button("Open to everyone") { state.openQueue(detail) }
                }
                Button(printer.enabled ? "Pause" : "Resume") { state.toggleEnabled(printer) }
                Button("Clear jobs") { state.clearJobs(on: printer) }
            }
            .controlSize(.small)
            .disabled(state.busy)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct StateBadge: View {
    let printer: Printer

    var body: some View {
        let (text, color): (String, Color) = {
            if printer.isStopped { return ("Paused", .orange) }
            if printer.isPrinting { return ("Printing", .blue) }
            if printer.isIdle { return ("Ready", .green) }
            return (printer.state.capitalized, .secondary)
        }()

        return Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

// MARK: - Sharing

struct SharingView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Printer Sharing").font(.title2.weight(.semibold))
                Text("Other Macs and iOS devices find shared printers over Bonjour. macOS sometimes locks a shared queue to specific users, which makes other machines park jobs with “Job held for authentication”. This screen fixes and prevents that.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: state.airPrintInstalled ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(state.airPrintInstalled ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Print from iPhone and iPad").font(.callout.weight(.medium))
                                Text(state.airPrintInstalled
                                     ? "On — every shared printer is advertised to iOS, and new ones are picked up automatically."
                                     : "Off. macOS shares printers with other Macs, but iOS ignores them: it needs the “_universal” subtype and a URF marker that Printer Sharing never publishes.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if state.airPrintInstalled {
                                Button("Turn off") { state.removeAirPrint() }
                            } else {
                                Button("Turn on") { state.installAirPrint() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        if state.airPrintInstalled {
                            Text("Nothing is proxied — jobs still go through CUPS and the queue's own driver. No administrator password is needed, because publishing a Bonjour service requires no privileges.")
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Share this Mac's printers on the network",
                               isOn: Binding(get: { state.sharingEnabled },
                                             set: { state.setSharing($0) }))
                            .toggleStyle(.switch)

                        Divider()

                        HStack(spacing: 10) {
                            Image(systemName: state.watcherInstalled ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(state.watcherInstalled ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Background watcher").font(.callout.weight(.medium))
                                Text(state.watcherInstalled
                                     ? "Watching every 60 seconds — queues reopen on their own."
                                     : "Not installed. Queues can silently lock again.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if state.watcherInstalled {
                                Button("Remove") { state.removeWatcher() }
                            } else {
                                Button("Install") { state.installWatcher() }
                            }
                        }
                    }
                    .padding(6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Shared queues").font(.headline)
                        Spacer()
                        Button("Fix all now") { state.fixSharingNow() }
                            .controlSize(.small)
                    }

                    let shared = state.detailedPrinters.filter(\.isShared)
                    if shared.isEmpty {
                        Text(state.sharingEnabled
                             ? "No queues are shared yet. Share one from the Printers tab."
                             : "Printer Sharing is off, so nothing is shared.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(shared) { printer in
                            HStack(spacing: 10) {
                                Image(systemName: printer.hasUserACL ? "lock.fill" : "lock.open.fill")
                                    .foregroundStyle(printer.hasUserACL ? .red : .green)
                                Text(printer.name)
                                Spacer()
                                if printer.hasUserACL {
                                    Text("Blocked").font(.caption).foregroundStyle(.red)
                                    Button("Open to everyone") { state.openQueue(printer) }
                                        .controlSize(.small)
                                } else {
                                    Text("Open to LAN").font(.caption).foregroundStyle(.green)
                                    Button("Restrict") { state.restrictQueue(printer) }
                                        .controlSize(.small)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor)))
                        }
                    }
                }

                if !state.unfinishedJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unfinished jobs").font(.headline)
                        ForEach(state.unfinishedJobs, id: \.self) { job in
                            Text(job).font(.system(.caption, design: .monospaced))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Watcher log").font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if state.shareLog.isEmpty {
                                Text("No entries yet.").foregroundStyle(.secondary).font(.caption)
                            } else {
                                ForEach(Array(state.shareLog.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(.caption2, design: .monospaced))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .disabled(state.busy)
    }
}

// MARK: - HP Laser 107a setup

struct SetupView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("HP Laser 107a").font(.title2.weight(.semibold))
                Text("This printer is a rebadged Samsung SL-M2026. It speaks Samsung's QPDL language over USB and has no Apple driver, so Printer Studio KH supplies one and then shares the queue to the network.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SetupStep(
                    number: 1,
                    title: "Connect the printer",
                    detail: state.laser107a != nil
                        ? "Detected on USB: \(state.laser107a!.name)"
                        : "Plug the printer into this Mac with a USB cable and switch it on. It is detected automatically.",
                    done: state.laser107a != nil)

                SetupStep(
                    number: 2,
                    title: "Install the print driver",
                    detail: Driver.isFilterInstalled
                        ? "Filter installed at \(Driver.installedFilter!)"
                        : "The splix rastertoqpdl filter and the HP Laser 10x PPD are not installed yet.",
                    done: Driver.isReady)

                SetupStep(
                    number: 3,
                    title: "Create the print queue",
                    detail: queueExists
                        ? "Queue “\(queueName ?? "")” exists."
                        : "Once the driver is installed, the queue is created automatically.",
                    done: queueExists)

                SetupStep(
                    number: 4,
                    title: "Share it with your devices",
                    detail: state.sharingEnabled
                        ? "Printer Sharing is on — iPhone, iPad and other Macs will see it."
                        : "Turn on Printer Sharing so your other devices can print to it.",
                    done: state.sharingEnabled)

                SetupStep(
                    number: 5,
                    title: "Release it from macOS's IPP-over-USB service",
                    detail: state.printerHeldByIPPUSB
                        ? "The printer is being held by ippusbd, so the queue will report “offline” and nothing will print. Turn on automatic release below."
                        : "Not held — CUPS has the device, so jobs can print.",
                    done: !state.printerHeldByIPPUSB)

                HStack(spacing: 10) {
                    Button("Set up the printer") { state.installDriver() }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.busy || !DriverInstaller.hasPayload)
                    Button("Keep ready after restarts") { state.releasePrinter() }
                        .disabled(state.busy || state.automaticUSBRelease)
                    Button("Remove driver") { state.uninstallDriver() }
                        .disabled(state.busy || !Driver.isFilterInstalled)
                    if state.busy {
                        ProgressView().controlSize(.small)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("About the original failure", systemImage: "lightbulb")
                            .font(.callout.weight(.medium))
                        Text("The earlier attempt built a QPDL encoder from scratch. It produced streams the printer accepted without any error, but it never fed paper. The cause is now known: this engine rejects a page whose band width is not exactly one of a fixed set of values, and it fails silently rather than reporting an error. The supported splix driver contains that table, which is why the app uses it instead of a hand-written encoder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                }

                if !state.usbDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("USB devices").font(.headline)
                        ForEach(state.usbDevices) { device in
                            HStack {
                                Image(systemName: device.isLaser107a ? "printer.fill" : "cable.connector")
                                Text(device.name)
                                Spacer()
                                Text("\(device.vendorID):\(device.productID)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private var queueName: String? {
        state.printers.first { $0.deviceURI.lowercased().contains("03f0") || $0.name.lowercased().contains("107") }?.name
    }

    private var queueExists: Bool { queueName != nil }
}

struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.2))
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Sticker sizes

/// Where label sizes are managed.
///
/// This screen exists because an iPhone cannot invent a page size. Its print
/// dialog offers exactly what the printer advertises and nothing more, so
/// customising has to happen here, on the Mac, and then shows up on every phone
/// that connects.
struct StickerSizesView: View {
    @EnvironmentObject var state: AppState

    private var targets: [String] {
        state.labelQueues.filter(\.isLabel).map(\.queue)
    }

    /// How many of a queue's advertised sizes are ours.
    private func countOfOurs(_ queue: String) -> Int {
        (state.offeredSizes[queue] ?? []).filter { $0.hasPrefix(PageSizeInstaller.marker) }.count
    }

    /// What a printer currently advertises, in the words a person would use.
    /// Kept out of the ViewBuilder: a `let` binding inside one confused
    /// ForEach overload resolution badly enough to pick the Binding variant.
    private func summary(for queue: String) -> String {
        let offered = (state.offeredSizes[queue] ?? []).count
        let ours = countOfOurs(queue)
        return ours == 0
            ? "offers \(offered) sizes — none of yours yet"
            : "offers \(offered) sizes, \(ours) of them yours"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sticker sizes").font(.title2.weight(.semibold))

                Text("Label printers ship with three sizes — 2 x 4, 4 x 4 and 4 x 6 inches — and none of them match real sticker stock. Add the sizes you actually use, and they appear in the page-size menu when you print from an iPhone or iPad.\n\nAn iPhone cannot enter a custom size: it offers exactly what the printer advertises. So this is where sizes are set — once here, usable from every phone.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text("On").frame(width: 30, alignment: .leading)
                            Text("Name").frame(width: 150, alignment: .leading)
                            Text("Width").frame(width: 80, alignment: .leading)
                            Text("Height").frame(width: 80, alignment: .leading)
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach($state.stickerSizes) { $size in
                            HStack(spacing: 8) {
                                Toggle("", isOn: $size.enabled)
                                    .labelsHidden()
                                    .frame(width: 30, alignment: .leading)
                                TextField("Name", text: $size.name)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 150)
                                TextField("mm", value: $size.widthMM, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                TextField("mm", value: $size.heightMM, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("mm").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    state.removeStickerSize(size.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove this size")
                            }
                        }
                    }
                    .padding(6)
                }

                HStack(spacing: 10) {
                    Button("Add a size") { state.addStickerSize() }
                    Button("Restore defaults") { state.resetStickerSizes() }
                    Spacer()
                    Button("Apply to printers") { state.applyStickerSizes() }
                        .buttonStyle(.borderedProminent)
                        .disabled(targets.isEmpty || state.busy)
                }
                .disabled(state.busy)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Where these go").font(.headline)
                        if targets.isEmpty {
                            Text("No label printer found yet. Install its driver and add it in System Settings > Printers & Scanners, then come back — the list updates itself.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(targets, id: \.self) { queue in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text(queue).font(.callout)
                                    }
                                    Text(summary(for: queue))
                                        .font(.caption)
                                        .foregroundStyle(countOfOurs(queue) > 0 ? .green : .secondary)
                                        .padding(.leading, 24)
                                }
                            }
                            Text("Applying rewrites each printer's PPD, so macOS will ask for your password once. Sizes already applied are replaced, never duplicated.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(6)
                }
            }
            .padding(24)
            .onChange(of: state.stickerSizes) { _ in
                state.saveStickerSizes()
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (build \(build))"
    }

    private var whatsNew: String? {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(.title2.weight(.semibold))

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Open Printer Studio KH at login",
                               isOn: Binding(get: { state.startsAtLogin },
                                             set: { state.setStartAtLogin($0) }))
                            .toggleStyle(.switch)
                        Toggle("Keep the USB printer ready after restarts",
                               isOn: Binding(get: { state.automaticUSBRelease },
                                             set: { state.setAutomaticUSBRelease($0) }))
                            .toggleStyle(.switch)
                            .disabled(state.busy)
                        Text("Automatic USB release needs administrator approval once. It runs at boot and after a replug, without opening this app or saving a password.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Starts the menu bar icon when you log in, without opening a window. The background services — keeping shared queues open, and the AirPrint advertisement — run at login independently of this.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About").font(.headline)
                        SettingsRow("Printer Studio KH", version)
                        if let whatsNew {
                            SettingsRow("What's new", whatsNew)
                        }
                        SettingsRow("Bundle", Bundle.main.bundleIdentifier ?? "—")
                        SettingsRow("System", ProcessInfo.processInfo.operatingSystemVersionString)
                        SettingsRow("Architecture", Self.architecture)
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Installed components").font(.headline)
                        SettingsRow("Print driver", Driver.isFilterInstalled
                                    ? (Driver.installedFilter ?? "installed")
                                    : "not installed",
                                    good: Driver.isFilterInstalled)
                        SettingsRow("PPD", Driver.isPPDInstalled ? "installed" : "not installed",
                                    good: Driver.isPPDInstalled)
                        SettingsRow("Share-fix watcher", state.watcherInstalled
                                    ? "installed, runs every 60s" : "not installed",
                                    good: state.watcherInstalled)
                        SettingsRow("AirPrint for iOS", state.airPrintInstalled
                                    ? "advertising shared printers" : "off",
                                    good: state.airPrintInstalled)
                        SettingsRow("Open at login", state.startsAtLogin ? "on" : "off",
                                    good: state.startsAtLogin)
                    }
                    .padding(6)
                }

                HStack(spacing: 10) {
                    Button("Read Me First") { state.openReadMe() }
                    Button("Refresh") { state.refreshNow() }
                    if let log = URL(string: "file://\(ShareFix.logFile.path)") {
                        Button("Show Log") { NSWorkspace.shared.open(log) }
                    }
                }
                .disabled(state.busy)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "unknown"
        #endif
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    var good: Bool?

    init(_ label: String, _ value: String, good: Bool? = nil) {
        self.label = label
        self.value = value
        self.good = good
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            if let good {
                Image(systemName: good ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(good ? .green : .secondary)
            }
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}

// MARK: - Activity

struct ActivityView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity").font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") { state.refreshNow() }.controlSize(.small)
            }

            if state.activity.isEmpty {
                EmptyState(title: "Nothing yet", symbol: "list.bullet.rectangle")
            } else {
                List(state.activity) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.kind.symbol)
                            .foregroundStyle(color(for: entry.kind))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(entry.timestamp)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(24)
    }

    private func color(for kind: LogEntry.Kind) -> Color {
        switch kind {
        case .info: return .accentColor
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
