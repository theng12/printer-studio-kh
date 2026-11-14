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
        case .stickers: return "Paper & Sticker Sizes"
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

/// Bare-styled footer controls drop their hover feedback; this puts it back so
/// every control has a hover state, not just a pressed one.
private final class HoverState: ObservableObject { @Published var isHovering = false }

private struct HoverHighlight<S: Shape>: ViewModifier {
    let shape: S
    // @StateObject rather than @State: this Command Line Tools install has no
    // SwiftUIMacros plugin, so @State does not build here (see HANDOFF notes).
    @StateObject private var hover = HoverState()

    func body(content: Content) -> some View {
        content
            .overlay(shape.fill(Palette.body.opacity(hover.isHovering ? 0.07 : 0)))
            .onHover { hover.isHovering = $0 }
    }
}

private extension View {
    func hoverHighlight<S: Shape>(_ shape: S) -> some View {
        modifier(HoverHighlight(shape: shape))
    }

    /// A card on the page: surface fill and a quiet border, one step above the
    /// page.
    func cardSurface(radius: CGFloat = 10) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.border, lineWidth: 1))
    }
}

/// Groups use the same surface and border as the standalone cards. The 5 pt
/// inset is the native GroupBox content inset (measured 260×160 box, 250×150
/// content), so the layout is unchanged.
struct CardGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
            configuration.content
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.border, lineWidth: 1))
    }
}

struct MainWindow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var checker = UpdateChecker()

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// The band carries one line only. Before anyone asks, it is the app's own
    /// summary; after a check it becomes that check's answer and stays there.
    private var footerStatus: String {
        checker.state == .notChecked ? state.statusSummary : checker.statusLine
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $state.screen) {
                    ForEach(Screen.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .scrollContentBackground(.hidden)
                Rectangle().fill(Palette.border).frame(height: 1)
                footer
            }
            .background(SidebarMaterial())
            .navigationSplitViewColumnWidth(min: 240, ideal: 248, max: 260)
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
            .background(Palette.page)
            .foregroundStyle(Palette.body)
            .groupBoxStyle(CardGroupStyle())
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
        .task {
            // Two copies would fight over the same launchd jobs; say so plainly
            // and let the newer one step aside.
            guard let other = Removal.anotherCopyIsRunning() else { return }
            let alert = NSAlert()
            alert.messageText = "Printer Studio KH is already running"
            alert.informativeText = "Another copy is open from \(other.path). This copy will quit so the two do not fight over the same background jobs."
            alert.addButton(withTitle: "Quit this copy")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// One left-aligned group, inside the sidebar so it shares its material.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(state.busyMessage).font(.caption).lineLimit(2)
                }
            }
            Button { openWindow(id: "support") } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart").font(.system(size: 13))
                    Text("Support this app").font(.system(size: 12))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Printer Studio KH is free. Leave a one-time donation if you like.")
            .accessibilityLabel("Support this app")
            .hoverHighlight(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                Button { openWindow(id: "whats-new") } label: {
                    HStack(spacing: 4) {
                        Text("Printer Studio KH").font(.system(size: 11, weight: .medium))
                        Text(version).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 26)
                    .background(Capsule().fill(Palette.surface))
                    .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("What's new in Printer Studio KH \(version)")
                .accessibilityLabel("Printer Studio KH \(version). Opens What's New.")
                .hoverHighlight(Capsule())

                Button { Task { await checker.check() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.surface))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(checker.state == .checking)
                .help("Check for updates")
                .accessibilityLabel("Check for updates")
                .hoverHighlight(RoundedRectangle(cornerRadius: 7))

                if let offered = checker.availableVersion {
                    Button { UpdaterHandoff.open() } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.accent.opacity(0.16)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Update to \(offered)")
                    .accessibilityLabel("Update to \(offered)")
                    .hoverHighlight(RoundedRectangle(cornerRadius: 7))
                }
            }

            Text(footerStatus)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .accessibilityAddTraits(.updatesFrequently)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 8)
    }
}


/// The sidebar's own material, for content that lives below the List.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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
                .foregroundStyle(Palette.muted)
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.muted)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
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
    var tint: Color = Palette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(Palette.muted)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardSurface()
    }
}

struct AdviceRow: View {
    let advice: DedupedAdvice

    private var tint: Color {
        switch advice.tint {
        case .danger: return Palette.danger
        case .warning: return Palette.warning
        case .accent: return Palette.accent
        case .muted: return Palette.muted
        case .success: return Palette.success
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: advice.symbol).foregroundStyle(tint).frame(width: 18)
            Text(advice.displayText).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle = advice.actionTitle, let action = advice.action {
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
                        .foregroundStyle(Palette.muted)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                    StatusCard(
                        title: "PRINTER SHARING",
                        value: state.sharingEnabled ? "On" : "Off",
                        symbol: state.sharingEnabled ? "checkmark.circle.fill" : "xmark.circle",
                        tint: state.sharingEnabled ? Palette.success : Palette.warning)
                        .frame(minHeight: 80, alignment: .topLeading)
                    StatusCard(
                        title: "PRINTERS",
                        value: "\(state.printers.count)",
                        symbol: "printer")
                        .frame(minHeight: 80, alignment: .topLeading)
                    StatusCard(
                        title: "QUEUES BLOCKED",
                        value: "\(state.queuesHeldShut.count)",
                        symbol: state.queuesHeldShut.isEmpty ? "checkmark.shield" : "exclamationmark.triangle.fill",
                        tint: state.queuesHeldShut.isEmpty ? Palette.success : Palette.danger)
                        .frame(minHeight: 80, alignment: .topLeading)
                    StatusCard(
                        title: "HP LASER 107a",
                        value: state.laser107a != nil ? "Connected" : "Not connected",
                        symbol: state.laser107a != nil ? "cable.connector" : "cable.connector.slash",
                        tint: state.laser107a != nil ? Palette.success : Palette.muted)
                        .frame(minHeight: 80, alignment: .topLeading)
                }

                let sections = WarningGrouper.group(adviceItems)
                if !sections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What needs doing").font(.headline)
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(section.title) (\(section.totalCount))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.muted)
                                ForEach(section.items) { item in
                                    AdviceRow(advice: item)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick actions").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
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

    private var adviceItems: [AdviceItem] {
        var items: [AdviceItem] = []

        if state.printerHeldByIPPUSB {
            items.append(AdviceItem(
                symbol: "exclamationmark.triangle.fill", tint: .danger, kind: .needsAttention,
                text: "macOS's IPP-over-USB service has claimed the printer. While it holds the device, CUPS cannot open it: the queue reports “offline” and jobs never print, with nothing logged to explain why. This comes back after a reboot or a replug.",
                actionTitle: "Release",
                action: { state.releasePrinter() }))
        }

        if !state.sharingEnabled {
            items.append(AdviceItem(
                symbol: "wifi.slash", tint: .warning, kind: .needsAttention,
                text: "Printer Sharing is off, so other devices on your network cannot see this Mac's printers.",
                actionTitle: "Turn on",
                action: { state.setSharing(true) }))
        }

        if !state.queuesHeldShut.isEmpty {
            let names = state.queuesHeldShut.map(\.displayName).joined(separator: ", ")
            items.append(AdviceItem(
                symbol: "lock.fill", tint: .danger, kind: .needsAttention,
                text: "\(names) \(state.queuesHeldShut.count == 1 ? "is" : "are") shared but locked to specific users. Other Macs will report “Job held for authentication”.",
                actionTitle: "Fix now",
                action: { state.fixSharingNow() }))
        }

        if state.sharingEnabled && !state.watcherInstalled {
            items.append(AdviceItem(
                symbol: "clock.arrow.circlepath", tint: .accent, kind: .suggestion,
                text: "The background watcher is not installed. Without it, re-saving the Sharing settings can lock the queues again.",
                actionTitle: "Install",
                action: { state.installWatcher() }))
        }

        if state.laser107a == nil {
            items.append(AdviceItem(
                symbol: "cable.connector", tint: .muted, kind: .suggestion,
                text: "The HP Laser 107a is not plugged in. Connect it by USB and it will appear here automatically."))
        } else if !Driver.isReady {
            items.append(AdviceItem(
                symbol: "shippingbox", tint: .warning, kind: .needsAttention,
                text: "The HP Laser 107a is connected but its print driver is not installed yet. Open the “HP Laser 107a” tab."))
        }

        return items
    }
}

// MARK: - Printers

struct PrintersView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(PrinterListMode.storageKey) private var modeRaw = PrinterListMode.defaultMode.rawValue

    private var mode: PrinterListMode { PrinterListMode.parse(modeRaw) }

    private var modeBinding: Binding<String> {
        Binding(get: { mode.rawValue }, set: { modeRaw = $0 })
    }

    private var modePicker: some View {
        Picker("View", selection: modeBinding) {
            Text("Cards").tag(PrinterListMode.cards.rawValue)
            Text("Table").tag(PrinterListMode.table.rawValue)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .labelsHidden()
        .help("Choose how to show printers")
        .accessibilityLabel("Printers view")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center) {
                        Text("Printers on this Mac").font(.title2.weight(.semibold))
                        Spacer()
                        modePicker
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Printers on this Mac").font(.title2.weight(.semibold))
                        modePicker
                    }
                }

                if state.printers.isEmpty {
                    EmptyState(title: "No printers", symbol: "printer.slash",
                               detail: "This Mac has no print queues yet.")
                        .frame(height: 240)
                } else if mode == .cards {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(state.printers) { printer in
                            PrinterCard(printer: printer)
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            PrinterTableHeader()
                            Divider()
                            ForEach(state.printers) { printer in
                                PrinterTableRow(printer: printer)
                                Divider()
                            }
                        }
                        .frame(minWidth: 760, alignment: .leading)
                    }
                    .cardSurface(radius: 10)
                }
            }
            .padding(24)
        }
    }
}

private struct PrinterMetricsGrid: View {
    let printer: Printer
    let detail: Printer?
    var labelWidth: CGFloat = 80

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Connection").foregroundStyle(Palette.muted).frame(width: labelWidth, alignment: .leading)
                Label(printer.friendlyLocation, systemImage: printer.transport.symbol)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let model = detail?.makeAndModel ?? (printer.makeAndModel.isEmpty ? nil : printer.makeAndModel) {
                GridRow {
                    Text("Model").foregroundStyle(Palette.muted).frame(width: labelWidth, alignment: .leading)
                    Text(model).fixedSize(horizontal: false, vertical: true)
                }
            }
            GridRow {
                Text("Shared").foregroundStyle(Palette.muted).frame(width: labelWidth, alignment: .leading)
                Text((detail?.isShared ?? printer.isShared) ? "Yes" : "No")
            }
            if let detail, detail.isShared {
                GridRow {
                    Text("Access").foregroundStyle(Palette.muted).frame(width: labelWidth, alignment: .leading)
                    if detail.hasUserACL {
                        Label("Locked to specific users", systemImage: "lock.fill").foregroundStyle(Palette.danger)
                    } else {
                        Label("Open to everyone", systemImage: "lock.open.fill").foregroundStyle(Palette.success)
                    }
                }
            }
        }
        .font(.callout)
    }
}

private struct PrinterActions: View {
    @EnvironmentObject var state: AppState
    let printer: Printer
    let detail: Printer?

    private var resolved: Printer { detail ?? printer }

    var body: some View {
        HStack(spacing: 8) {
            Button("Print test page") { state.testPrint(printer) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Print one test page to \(printer.displayName)")
            Menu {
                Button(resolved.isShared ? "Stop sharing" : "Share") {
                    state.toggleShared(resolved)
                }
                if resolved.isHeldShut {
                    Button("Open to everyone") { state.openQueue(resolved) }
                }
                Button(printer.enabled ? "Pause" : "Resume") { state.toggleEnabled(printer) }
                Button("Clear jobs") { state.clearJobs(on: printer) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More actions for \(printer.displayName)")
            .accessibilityLabel("More actions for \(printer.displayName)")
        }
        .disabled(state.busy)
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
                    .foregroundStyle(printer.isStopped ? Palette.warning : Palette.accent)
                Text(printer.displayName).font(.headline).lineLimit(1)
                Spacer()
                StateBadge(printer: printer)
            }

            HStack {
                TextField("Printer name", text: Binding(
                    get: { state.printerNameDrafts[printer.name] ?? printer.displayName },
                    set: { state.printerNameDrafts[printer.name] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Printer name")
                Button("Save name") { state.renamePrinter(printer) }
                    .disabled(state.busy || (state.printerNameDrafts[printer.name] ?? printer.displayName) == printer.displayName)
            }

            if printer.transport != .usb {
                Text("This name is for Mac sharing. A network printer’s own AirPrint name is set on the printer.")
                    .font(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let choices = state.paperChoices[printer.name], !choices.isEmpty {
                Picker("Paper size", selection: Binding(
                    get: { state.selectedPaper[printer.name] ?? "" },
                    set: { state.selectPaper($0, for: printer) }
                )) {
                    if !(choices.contains { $0.key == state.selectedPaper[printer.name] }) {
                        Text("Choose a size").tag("")
                    }
                    ForEach(choices, id: \.key) { paper in
                        Text(paper.label).tag(paper.key)
                    }
                }
                .disabled(state.busy)
                Text("Use the stock loaded in the printer. Reopen the phone or Mac print dialog after changing it; choose the same size there. Test page uses this size and prints one page.")
                    .font(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrinterMetricsGrid(printer: printer, detail: detail, labelWidth: 90)

            Spacer(minLength: 0)

            PrinterActions(printer: printer, detail: detail)
        }
        .padding(14)
        .frame(minHeight: 320, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardSurface()
    }
}

private struct PrinterTableHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Connection").frame(width: 170, alignment: .leading)
            Text("State").frame(width: 96, alignment: .leading)
            Text("Shared").frame(width: 64, alignment: .leading)
            Text("Paper").frame(width: 150, alignment: .leading)
            Text("Actions").fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct PrinterTableRow: View {
    @EnvironmentObject var state: AppState
    let printer: Printer

    private var detail: Printer? {
        state.detailedPrinters.first { $0.name == printer.name }
    }

    private func stateText(_ printer: Printer) -> String {
        if printer.isStopped { return "Paused" }
        if printer.isPrinting { return "Printing" }
        if printer.isIdle { return "Ready" }
        return printer.state.capitalized
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(printer.displayName).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    TextField("Name", text: Binding(
                        get: { state.printerNameDrafts[printer.name] ?? printer.displayName },
                        set: { state.printerNameDrafts[printer.name] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(minWidth: 120)
                    .accessibilityLabel("Printer name")
                    Button("Save name") { state.renamePrinter(printer) }
                        .controlSize(.small)
                        .disabled(state.busy || (state.printerNameDrafts[printer.name] ?? printer.displayName) == printer.displayName)
                }
                if printer.transport != .usb {
                    Text("Mac sharing name only. Network printer AirPrint name is set on the printer.")
                        .font(.caption2).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Label(printer.friendlyLocation, systemImage: printer.transport.symbol)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let model = detail?.makeAndModel ?? (printer.makeAndModel.isEmpty ? nil : printer.makeAndModel) {
                    Text(model).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 170, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(stateText(printer)).font(.callout)
                StateBadge(printer: printer)
            }
            .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text((detail?.isShared ?? printer.isShared) ? "Yes" : "No").font(.callout)
                if let detail, detail.isShared {
                    if detail.hasUserACL {
                        Text("Locked").font(.caption).foregroundStyle(Palette.danger)
                    } else {
                        Text("Open").font(.caption).foregroundStyle(Palette.success)
                    }
                }
            }
            .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if let choices = state.paperChoices[printer.name], !choices.isEmpty {
                    Picker("Paper", selection: Binding(
                        get: { state.selectedPaper[printer.name] ?? "" },
                        set: { state.selectPaper($0, for: printer) }
                    )) {
                        if !(choices.contains { $0.key == state.selectedPaper[printer.name] }) {
                            Text("Choose").tag("")
                        }
                        ForEach(choices, id: \.key) { paper in
                            Text(paper.label).tag(paper.key)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(state.busy)
                    .accessibilityLabel("Paper size for \(printer.displayName)")
                } else {
                    Text("—").foregroundStyle(Palette.muted).font(.callout)
                }
            }
            .frame(width: 150, alignment: .leading)

            PrinterActions(printer: printer, detail: detail)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct StateBadge: View {
    let printer: Printer

    var body: some View {
        let (text, color): (String, Color) = {
            if printer.isStopped { return ("Paused", Palette.warning) }
            if printer.isPrinting { return ("Printing", Palette.accent) }
            if printer.isIdle { return ("Ready", Palette.success) }
            return (printer.state.capitalized, Palette.muted)
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
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: state.airPrintInstalled && state.sharingEnabled ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(state.airPrintInstalled && state.sharingEnabled ? Palette.success : Palette.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Print from iPhone and iPad").font(.callout.weight(.medium))
                                Text(!state.sharingEnabled
                                     ? "Printer Sharing is off. Turn on AirPrint to enable sharing and make shared printers available on your network."
                                     : state.airPrintInstalled
                                     ? "Enabled — every shared printer is announced as its name followed by (AirPrint). iPhone visibility is not checked until you see the printers on your phone."
                                     : "Off. Turn on to announce every shared printer to iPhone and iPad.")
                                    .font(.caption).foregroundStyle(Palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if state.airPrintInstalled && state.sharingEnabled {
                                Button("Turn off") { state.removeAirPrint() }
                            } else {
                                Button("Turn on") { state.installAirPrint() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        if state.labelPrintingNeedsSetup {
                            HStack {
                                Text("Label printing needs a one-time driver update. After setup, test one label from your iPhone.")
                                    .font(.caption).foregroundStyle(Palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button("Set up label printing") { state.setupLabelPrinting() }
                                    .disabled(state.busy)
                            }
                        }
                        if state.labelQueues.contains(where: { $0.isLabel }) {
                            Text("iPhone output is not checked by this app. Test one label from your iPhone after setup.")
                                .font(.caption2).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if state.airPrintInstalled {
                            Text("Jobs go through this Mac's print service and the printer's driver. Turning on Printer Sharing may ask for administrator approval.")
                                .font(.caption2).foregroundStyle(Palette.muted)
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
                                .foregroundStyle(state.watcherInstalled ? Palette.success : Palette.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Background watcher").font(.callout.weight(.medium))
                                Text(state.watcherInstalled
                                     ? "Watching every 60 seconds — queues reopen on their own."
                                     : "Not installed. Queues can silently lock again.")
                                    .font(.caption).foregroundStyle(Palette.muted)
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
                            .foregroundStyle(Palette.muted).font(.callout)
                    } else {
                        ForEach(shared) { printer in
                            HStack(spacing: 10) {
                                Image(systemName: printer.hasUserACL ? "lock.fill" : "lock.open.fill")
                                    .foregroundStyle(printer.hasUserACL ? Palette.danger : Palette.success)
                                Text(printer.displayName)
                                Spacer()
                                if printer.hasUserACL {
                                    Text("Blocked").font(.caption).foregroundStyle(Palette.danger)
                                    Button("Open to everyone") { state.openQueue(printer) }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .help("Open \(printer.displayName) to everyone")
                                } else {
                                    Text("Open to LAN").font(.caption).foregroundStyle(Palette.success)
                                    Menu {
                                        Button("Restrict") { state.restrictQueue(printer) }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .frame(width: 22, height: 22)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                    .help("More actions for \(printer.displayName)")
                                    .accessibilityLabel("More actions for \(printer.displayName)")
                                }
                            }
                            .padding(10)
                            .cardSurface(radius: 8)
                        }
                    }
                }

                if !state.unfinishedJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unfinished jobs").font(.headline)
                        ForEach(StringDeduper.dedupe(state.unfinishedJobs)) { job in
                            Text(job.display).font(.system(.caption, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Watcher log").font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if state.shareLog.isEmpty {
                                Text("No entries yet.").foregroundStyle(Palette.muted).font(.caption)
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
                    .cardSurface(radius: 8)
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
                    .foregroundStyle(Palette.muted)
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

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
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
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                }

                if !state.usbDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("USB devices").font(.headline)
                        ForEach(USBDeduper.group(state.usbDevices)) { device in
                            HStack {
                                Image(systemName: device.isLaser107a ? "printer.fill" : "cable.connector")
                                Text(device.name)
                                if device.count > 1 {
                                    Text("×\(device.count)")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Text("\(device.vendorID):\(device.productID)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Palette.muted)
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
                Circle().fill(done ? Palette.success : Palette.muted.opacity(0.2))
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .cardSurface()
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
                Text("Paper & sticker sizes").font(.title2.weight(.semibold))

                Text("Set the sizes here for AirPrint to read from your shared printer. Width and height follow how the stock feeds into the printer. You can edit any size or turn it off.\n\nCustom sizes apply to label printers within their driver’s limits. A4 and A5 are already standard choices on the HP Laser queue; use that printer’s paper-size menu. A narrow label printer cannot print an A4 or A5 sheet.")
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Text("On").frame(width: 30, alignment: .leading)
                                Text("Name").frame(width: 150, alignment: .leading)
                                Text("Width (mm)").frame(width: 80, alignment: .leading)
                                Text("Height (mm)").frame(width: 80, alignment: .leading)
                                Text("Inches").frame(width: 150, alignment: .leading)
                                Spacer(minLength: 0)
                            }
                            .font(.caption)
                            .foregroundStyle(Palette.muted)

                            ForEach($state.stickerSizes) { $size in
                                HStack(spacing: 8) {
                                    Toggle("", isOn: $size.enabled)
                                        .labelsHidden()
                                        .frame(width: 30, alignment: .leading)
                                        .help("Include this size")
                                        .accessibilityLabel("Include \(size.name)")
                                    TextField("Name", text: $size.name)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 150)
                                    TextField("mm", value: $size.widthMM, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    TextField("mm", value: $size.heightMM, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Text(size.inchesLabel + " in")
                                        .font(.callout)
                                        .foregroundStyle(Palette.muted)
                                        .frame(width: 150, alignment: .leading)
                                        .textSelection(.enabled)
                                    Spacer(minLength: 0)
                                    Button {
                                        state.removeStickerSize(size.id)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove this size")
                                    .accessibilityLabel("Remove \(size.name)")
                                }
                            }
                        }
                        .frame(minWidth: 600, alignment: .leading)
                        .padding(6)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                    Button("Add a size") { state.addStickerSize() }
                    Button("Restore defaults") { state.resetStickerSizes() }
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
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(targets, id: \.self) { queue in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Palette.success)
                                        Text(state.printers.first { $0.name == queue }?.displayName ?? queue).font(.callout)
                                    }
                                    Text(summary(for: queue))
                                        .font(.caption)
                                        .foregroundStyle(countOfOurs(queue) > 0 ? Palette.success : Palette.muted)
                                        .padding(.leading, 24)
                                    Text(PageSizeInstaller.queueSummary(queue: queue, sizes: state.stickerSizes))
                                        .font(.caption)
                                        .foregroundStyle(Palette.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                        .padding(.leading, 24)
                                }
                            }
                            Text("Apply adds only sizes supported by each label printer’s driver. macOS asks for administrator approval. Reopen the iPhone or iPad print dialog afterward; the choices shown can vary by app and iOS version.")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
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

// MARK: - What's New

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var notes: String {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Release notes could not be loaded for this version."
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What's New").font(.title2.weight(.semibold))
                Text("Printer Studio KH \(version)").foregroundStyle(Palette.muted)
            }
            ScrollView {
                Text(notes)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 240)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @State private var confirmingRemoval = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (build \(build))"
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
                            .font(.caption).foregroundStyle(Palette.muted)
                        Text("Starts the menu bar icon when you log in, without opening a window. The background services — keeping shared queues open, and the AirPrint advertisement — run at login independently of this.")
                            .font(.caption).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Appearance").font(.headline)
                        Picker("Appearance", selection: $appearanceRaw) {
                            ForEach(Appearance.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text("System follows macOS and is where every install starts.")
                            .font(.caption).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About").font(.headline)
                        SettingsRow("Printer Studio KH", version)
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

                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                        Button("Read Me First") { state.openReadMe() }
                        Button("Refresh") { state.refreshNow() }
                        if let log = URL(string: "file://\(ShareFix.logFile.path)") {
                            Button("Show Log") { NSWorkspace.shared.open(log) }
                        }
                        Button("Copy Error Report") { state.copyErrorReport() }
                            .disabled(state.reportFeedback == "Generating…")
                    }
                    .disabled(state.busy)
                    if let feedback = state.reportFeedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(feedback.contains("Failed") ? Palette.danger : Palette.muted)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Remove from this Mac").font(.headline)
                        Text("Stops the background helpers, unloads their launchd jobs, removes the login item and moves the app to the Trash. Your settings and saved sticker sizes stay, and the printer queues and driver are left alone.")
                            .font(.caption).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Remove Printer Studio KH…") { confirmingRemoval = true }
                            .confirmationDialog("Remove Printer Studio KH from this Mac?",
                                                isPresented: $confirmingRemoval) {
                                Button("Remove", role: .destructive) { state.removeEverything() }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("The app quits when this finishes.")
                            }
                    }
                    .padding(6)
                }

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
                .foregroundStyle(Palette.muted)
                .frame(width: 150, alignment: .leading)
            if let good {
                Image(systemName: good ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(good ? Palette.success : Palette.muted)
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
                List(ActivityDeduper.condense(state.activity)) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.kind.symbol)
                            .foregroundStyle(color(for: entry.kind))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayMessage)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(entry.timestamp)
                                .font(.caption2)
                                .foregroundStyle(Palette.muted)
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
        case .info: return Palette.accent
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .error: return Palette.danger
        }
    }
}
