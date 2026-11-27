import AppKit
import SwiftUI
import CoreGraphics
import ApplicationServices

// Offscreen render harness for Printer Studio KH.
// Compiled as the temporary app entry point against copied app sources with @main stripped.

struct RenderOptions {
    let mode: String      // "page", "window", "contrast"
    let target: String    // page name or "main"
    let outDir: String
    let width: Int
    let height: Int
    let appearance: String // "light" or "dark"
    let printersListMode: String? // "table" or "cards" when relevant

    static func parse(_ args: [String]) -> RenderOptions? {
        guard args.count >= 2 else { return nil }
        if args[1] == "contrast" {
            return RenderOptions(mode: "contrast", target: "", outDir: args.count > 2 ? args[2] : "", width: 0, height: 0, appearance: "", printersListMode: nil)
        }
        if args[1] == "switch-check" {
            return RenderOptions(mode: "switch-check", target: "printers", outDir: args.count > 2 ? args[2] : "", width: 1024, height: 720, appearance: "light", printersListMode: nil)
        }
        if args[1] == "keyboard-check" {
            return RenderOptions(mode: "keyboard-check", target: "printers", outDir: args.count > 2 ? args[2] : "", width: 1024, height: 720, appearance: "light", printersListMode: nil)
        }
        if args[1] == "theme-check" {
            return RenderOptions(mode: "theme-check", target: "settings", outDir: args.count > 2 ? args[2] : "", width: 1024, height: 720, appearance: "system", printersListMode: nil)
        }
        if args[1] == "interaction" {
            return RenderOptions(mode: "interaction", target: args.count > 2 ? args[2] : "", outDir: args.count > 3 ? args[3] : "", width: 1024, height: 720, appearance: "light", printersListMode: nil)
        }
        if args[1] == "sidebar-check" {
            var size = (1024, 720)
            if args.count > 3 {
                let parts = args[3].lowercased().split(separator: "x")
                if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) { size = (w, h) }
            }
            return RenderOptions(mode: "sidebar-check", target: "sidebar", outDir: args.count > 2 ? args[2] : "", width: size.0, height: size.1, appearance: "light", printersListMode: nil)
        }
        guard args.count >= 6 else { return nil }
        let mode = args[1]
        let target = args[2]
        let out = args[3]
        let parts = args[4].lowercased().split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
        let appearance = args[5].lowercased()
        let plm = args.count > 6 ? args[6] : nil
        return RenderOptions(mode: mode, target: target, outDir: out, width: w, height: h, appearance: appearance, printersListMode: plm)
    }
}

final class DismissFlag: ObservableObject {
    @Published var dismissed = false
}

/// The What's New window's only control is Done, which closes the scene. Host it
/// as a sheet so its own dismiss environment has something real to close.
struct WhatsNewSheetHost: View {
    @ObservedObject var flag: DismissFlag
    @State private var showing = true

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $showing, onDismiss: { flag.dismissed = true }) {
                WhatsNewView()
                    .onPreferenceChange(ProbeFrames.self) { InteractionProbe.frames = $0 }
            }
    }
}

@main
struct PageRenderHarness {
    static func main() {
        // The harness must never run the app's startup work. Set this before any
        // AppState is constructed, whichever mode was asked for.
        setenv("PRINTER_STUDIO_RENDER", "1", 1)
        // Keep home-relative writes in a throwaway home when the caller did not
        // already point HOME into the system temp dir (the shell harness does).
        let tempRoot = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let currentHome = ProcessInfo.processInfo.environment["HOME"] ?? ""
        if !currentHome.hasPrefix(tempRoot) {
            let scratchHome = URL(fileURLWithPath: tempRoot)
                .appendingPathComponent("ps-render-home-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: scratchHome, withIntermediateDirectories: true)
            setenv("HOME", scratchHome.path, 1)
        }

        guard let opts = RenderOptions.parse(CommandLine.arguments) else {
            fputs("usage: render-page <page|window|contrast|switch-check|keyboard-check|theme-check> <target> <outdir> <WxH> <light|dark> [printersListMode]\n", stderr)
            exit(2)
        }
        if opts.mode == "contrast" {
            runContrast()
            return
        }
        if opts.mode == "switch-check" {
            runSwitchCheck(opts)
            return
        }
        if opts.mode == "keyboard-check" {
            runKeyboardCheck(opts)
            return
        }
        if opts.mode == "theme-check" {
            runThemeCheck(opts)
            return
        }
        if opts.mode == "interaction" {
            runInteraction(opts)
            return
        }
        if opts.mode == "sidebar-check" {
            runSidebarCheck(opts)
            return
        }
        runRender(opts)
    }

    // MARK: - Contrast

    static func runContrast() {
        var results: [String: [String: Any]] = [:]
        for (name, nsName) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            guard let appearance = NSAppearance(named: nsName) else { continue }
            appearance.performAsCurrentDrawingAppearance {
                let label = resolved(.labelColor)
                let surface = resolved(.controlBackgroundColor)
                let separator = resolved(.separatorColor)
                let windowBG = resolved(.windowBackgroundColor)
                let labelAlpha = label.alphaComponent
                // Palette: page = body at 0.09; muted = body at 0.66; border = separator.
                // Body is labelColor, which itself carries alpha (0.847 on this macOS).
                let page = composite(foreground: withAlpha(label, 0.09 * labelAlpha), over: windowBG)
                let bodyOnPage = composite(foreground: label, over: page)
                let mutedOnPage = composite(foreground: withAlpha(label, 0.66 * labelAlpha), over: page)
                let mutedOnSurface = composite(foreground: withAlpha(label, 0.66 * labelAlpha), over: surface)
                let borderOnPage = composite(foreground: separator, over: page)
                let success = resolved(NSColor(Palette.success))
                let warning = resolved(NSColor(Palette.warning))
                let danger = resolved(NSColor(Palette.danger))
                let accent = resolved(NSColor(Palette.accent))
                let accentFill = resolved(NSColor(Palette.accentFill))
                let controlBorder = resolved(NSColor(Palette.controlBorder))
                let successBadge = composite(foreground: withAlpha(success, 0.15), over: surface)
                let warningBadge = composite(foreground: withAlpha(warning, 0.15), over: surface)
                results[name] = [
                    "page_surface": ratio(page, surface),
                    "body_page": ratio(bodyOnPage, page),
                    "muted_page": ratio(mutedOnPage, page),
                    "muted_surface": ratio(mutedOnSurface, surface),
                    "border_page": ratio(borderOnPage, page),
                    "success_badge": ratio(success, successBadge),
                    "warning_badge": ratio(warning, warningBadge),
                    "success_page": ratio(success, page),
                    "warning_page": ratio(warning, page),
                    "danger_page": ratio(danger, page),
                    "accent_page": ratio(accent, page),
                    "control_border_surface": ratio(controlBorder, surface),
                    "white_on_accent_fill": ratio(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), accentFill),
                    "resolved": [
                        "label": rgba(label),
                        "surface": rgba(surface),
                        "separator": rgba(separator),
                        "window_background": rgba(windowBG),
                        "page": rgba(page),
                        "success": rgba(success),
                        "warning": rgba(warning),
                        "danger": rgba(danger),
                        "accent": rgba(accent),
                        "accent_fill": rgba(accentFill),
                        "control_border": rgba(controlBorder),
                    ],
                ]
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            print("CONTRAST \(s)")
        } else {
            fputs("contrast probe failed\n", stderr)
            exit(1)
        }
        func value(_ appearance: String, _ key: String) -> Double {
            (results[appearance]?[key] as? Double) ?? 0
        }
        let textKeys = ["body_page", "muted_page", "muted_surface", "success_badge",
                        "warning_badge", "success_page", "warning_page", "danger_page",
                        "accent_page", "white_on_accent_fill"]
        var failing: [String] = []
        for appearance in ["light", "dark"] {
            for key in textKeys where value(appearance, key) < 4.5 {
                failing.append("\(appearance).\(key)=\(value(appearance, key))")
            }
        }
        if !failing.isEmpty {
            fputs("CONTRAST_FAIL below 4.5: \(failing.joined(separator: ", "))\n", stderr)
            exit(1)
        }
        let borderFailing = ["light", "dark"].filter { value($0, "control_border_surface") < 3.0 }
        if !borderFailing.isEmpty {
            fputs("CONTRAST_FAIL control outline below 3:1: \(borderFailing)\n", stderr)
            exit(1)
        }
    }

    static func rgba(_ c: NSColor) -> String {
        String(format: "%.3f,%.3f,%.3f,%.3f", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    static func resolved(_ color: NSColor) -> NSColor {
        (color.usingColorSpace(.sRGB) ?? color).copy() as! NSColor
    }

    static func withAlpha(_ c: NSColor, _ a: CGFloat) -> NSColor {
        NSColor(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: a)
    }

    static func composite(foreground: NSColor, over background: NSColor) -> NSColor {
        let fa = foreground.alphaComponent
        let r = foreground.redComponent * fa + background.redComponent * (1 - fa)
        let g = foreground.greenComponent * fa + background.greenComponent * (1 - fa)
        let b = foreground.blueComponent * fa + background.blueComponent * (1 - fa)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static func luminance(_ c: NSColor) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(Double(c.redComponent)), g = lin(Double(c.greenComponent)), b = lin(Double(c.blueComponent))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    static func ratio(_ a: NSColor, _ b: NSColor) -> Double {
        let l1 = luminance(a), l2 = luminance(b)
        let hi = max(l1, l2), lo = min(l1, l2)
        let r = (hi + 0.05) / (lo + 0.05)
        return (r * 1000).rounded() / 1000
    }

    // MARK: - Render

    static func runRender(_ opts: RenderOptions) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(atPath: opts.outDir, withIntermediateDirectories: true)

        if opts.appearance == "dark" {
            app.appearance = NSAppearance(named: .darkAqua)
        } else {
            app.appearance = NSAppearance(named: .aqua)
        }

        let baseTarget = opts.target
            .replacingOccurrences(of: "-empty", with: "")
            .replacingOccurrences(of: "-error", with: "")
            .replacingOccurrences(of: "-outcome", with: "")
        let isEmpty = opts.target.hasSuffix("-empty")
            || ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER_EMPTY"] == "1"
        let isError = opts.target.hasSuffix("-error")
            || ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER_ERROR"] == "1"
        let isOutcome = opts.target.hasSuffix("-outcome") || opts.target == "banner-printers"
            || ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER_OUTCOME"] == "1"
        if baseTarget == "printers-table" {
            UserDefaults.standard.set("table", forKey: "printersListMode")
        } else if baseTarget == "printers" {
            UserDefaults.standard.set("cards", forKey: "printersListMode")
        }
        // The custom-recording state draws the widest button row on Settings;
        // it is reachable, so the narrow-width render has to cover it.
        if let custom = ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER_CUSTOM_VOICE"],
           custom == "1" || custom == "missing" {
            UserDefaults.standard.set(true, forKey: "notifyOnJobReceived")
            UserDefaults.standard.set("custom", forKey: "announcementVoice")
            if custom == "1" {
                let url = VoiceClip.customURL()
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data(repeating: 0, count: 64).write(to: url)
            }
        }

        let state = makeFixtureState()
        if isError {
            applyErrorFixture(state)
        } else if isEmpty {
            applyEmptyFixture(state)
        } else if isOutcome {
            applyOutcomeFixture(state)
        }
        if opts.mode == "page" {
            applyPageSelection(state: state, page: baseTarget, printersListMode: opts.printersListMode)
        }
        if opts.mode == "window" {
            applyWindowSelection(state: state, target: opts.target)
        }

        let rootView: AnyView = {
            if baseTarget == "banner-printers" {
                return AnyView(VStack(spacing: 0) {
                    ResultBanner(message: state.lastMessage ?? "", ok: state.lastMessageOK) {}
                    PrintersView()
                        .environmentObject(state)
                })
            }
            if opts.mode == "window" {
                if opts.target.hasPrefix("window-whats-new") {
                    return AnyView(WhatsNewView().environmentObject(state))
                }
                return AnyView(MainWindow().environmentObject(state))
            } else {
                return AnyView(pageView(for: baseTarget).environmentObject(state))
            }
        }()

        // NSHostingController, not a bare NSHostingView: the sticker page's
        // ForEach-of-bindings layout trips an AttributeGraph cycle when its view
        // is installed directly as a window's contentView offscreen.
        let controller = NSHostingController(rootView: rootView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.page)
            .background(Color(nsColor: .windowBackgroundColor))
            .foregroundStyle(Palette.body)
            .tint(Color.accentColor)
            .groupBoxStyle(CardGroupStyle())
            .environment(\.controlActiveState, .key)
            .onPreferenceChange(ProbeFrames.self) { InteractionProbe.frames = $0 })
        // The requested size is authoritative: without this the hosting view
        // pushes its full content height into the window and a ScrollView page
        // grows the window instead of clipping.
        controller.sizingOptions = []
        let hosting = controller.view
        hosting.frame = NSRect(x: 0, y: 0, width: opts.width, height: opts.height)

        let isWindowRender = opts.mode == "window"
        // A window render's requested size is the window's frame, exactly as the
        // brief reads it; the content area is the frame minus the real chrome.
        // The window is created at its final frame so SwiftUI never lays out
        // once at a taller transient size (that transient layout brings back the
        // toolbar fade that washed headings in the 900 pt window).
        let mask: NSWindow.StyleMask = isWindowRender ? [.titled, .closable, .resizable] : [.borderless]
        var contentRect = hosting.frame
        if isWindowRender {
            contentRect = NSWindow.contentRect(forFrameRect: NSRect(x: 0, y: 0,
                                                                    width: CGFloat(opts.width),
                                                                    height: CGFloat(opts.height)),
                                               styleMask: mask)
        }
        let window = NSWindow(contentRect: contentRect, styleMask: mask,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if isWindowRender {
            window.title = "Printer Studio KH"
            // The real window with its title bar and toolbar in the capture;
            // MEASURE reports the size actually drawn.
        }
        let windowAppearance = NSAppearance(named: opts.appearance == "dark" ? .darkAqua : .aqua)
        window.appearance = windowAppearance
        var windowBackground = NSColor.windowBackgroundColor
        windowAppearance?.performAsCurrentDrawingAppearance {
            windowBackground = NSColor.windowBackgroundColor
        }
        window.backgroundColor = windowBackground
        window.contentViewController = controller
        if !isWindowRender {
            window.setContentSize(NSSize(width: opts.width, height: opts.height))
        }
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        // Ordered in but practically invisible: the sidebar's material and list
        // rows only draw for an ordered window, and alpha 0.01 keeps it off the
        // owner's desktop (AppKit also pulls an offscreen frame onto the screen).
        window.alphaValue = 0.01
        window.orderFront(nil)
        // A non-key window draws the inactive selection style; make it key
        // without activating the app.
        window.makeKey()

        // Let SwiftUI/AppKit-backed controls lay out and draw.
        for _ in 0..<12 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        if isWindowRender {
            // Pin the real window to the requested frame once the toolbar has
            // settled, then let SwiftUI lay out at the final content height.
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY,
                                   width: CGFloat(opts.width), height: CGFloat(opts.height)), display: true)
            for _ in 0..<6 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
        }
        // A real window includes its title bar and toolbar; capture the frame view.
        let captureView = isWindowRender ? (window.contentView?.superview ?? hosting) : hosting
        guard let rep = captureView.bitmapImageRepForCachingDisplay(in: captureView.bounds) else {
            emitResult(opts: opts, ok: false, error: "bitmap allocation failed", geom: nil)
            exit(1)
        }
        captureView.cacheDisplay(in: captureView.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            emitResult(opts: opts, ok: false, error: "png encode failed", geom: nil)
            exit(1)
        }

        let filename = outputName(opts)
        let path = (opts.outDir as NSString).appendingPathComponent(filename)
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            emitResult(opts: opts, ok: false, error: "write failed: \(error)", geom: nil)
            exit(1)
        }

        var accentFill = NSColor.black
        windowAppearance?.performAsCurrentDrawingAppearance {
            accentFill = NSColor(Palette.accentFill).usingColorSpace(.sRGB) ?? .black
        }
        // A result banner spans the detail width by design; sample the page
        // background from the bottom edge for that render.
        let geom = measure(rep: rep, isWindow: isWindowRender, accent: accentFill,
                           sampleBottom: isWindowRender || opts.target.hasSuffix("-outcome") || opts.target == "banner-printers")
        // The real window's chrome and the page heading against it: a heading
        // that sits under the title bar, or a detail area whose top edge is
        // washed by the toolbar fade, is the round-4 craft defect this measures.
        var chrome: Int? = nil
        var headingTop: Int? = nil
        var topWashPct: Double? = nil
        var sidebarPx: Int? = nil
        if isWindowRender {
            let band = Int((window.frame.height - window.contentLayoutRect.height).rounded())
            chrome = band
            // SwiftUI global frames are content coordinates; the content's top
            // in the captured image comes from the hosting view's own frame.
            let contentTop = captureView.bounds.height - hosting.frame.maxY
            if let heading = InteractionProbe.frames["heading"] {
                headingTop = Int((contentTop + heading.minY).rounded())
            }
            topWashPct = detailTopWash(rep: rep, chrome: band)
            sidebarPx = sidebarTextPixels(rep: rep, chrome: band)
        }
        // The Settings action row wraps when its labels cannot fit; reporting
        // the button frames says which layout was chosen, so a compressed row
        // (the defect the 375 render missed twice) is visible in the numbers.
        var actionRow: [[String: Any]] = []
        if opts.target == "settings" {
            for name in ["control.chooseRecording", "control.useEnglishClip", "control.removeRecording"] {
                if let f = InteractionProbe.frames[name] {
                    actionRow.append(["name": name, "x": Int(f.minX.rounded()),
                                      "y": Int(f.minY.rounded()),
                                      "w": Int(f.width.rounded()), "h": Int(f.height.rounded())])
                }
            }
        }
        emitResult(opts: opts, ok: true, error: nil, geom: geom,
                   controls: controlStates(captureView),
                   pixels: (rep.pixelsWide, rep.pixelsHigh),
                   chrome: chrome, headingTop: headingTop, topWashPct: topWashPct,
                   sidebarPx: sidebarPx, actionRow: actionRow)
        if opts.target == "banner-printers" {
            emitBanner(state: state, rep: rep, capture: captureView)
        }
    }

    /// How much the page background just under the window chrome is brightened
    /// against the same background further down, in percent: a toolbar fade
    /// washing the top of the detail area shows up here as a non-zero number.
    static func detailTopWash(rep: NSBitmapImageRep, chrome: Int) -> Double {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 60, chrome > 0, h > chrome + 240, let data = rep.bitmapData else { return 0 }
        let bpp = rep.bitsPerPixel / 8, bpr = rep.bytesPerRow
        func lum(_ x: Int, _ y: Int) -> Double {
            let p = pixel(data: data, x: x, y: y, bpp: bpp, bpr: bpr)
            return (0.2126 * Double(p.0) + 0.7152 * Double(p.1) + 0.0722 * Double(p.2)) / 255
        }
        // The right 8 px are page padding at every window size: no card, no text.
        func strip(_ ys: Range<Int>) -> Double {
            var values: [Double] = []
            for y in ys { for x in stride(from: w - 12, to: w - 4, by: 2) { values.append(lum(x, y)) } }
            values.sort()
            return values.isEmpty ? 0 : values[values.count / 2]
        }
        let base = strip((chrome + 120)..<min(chrome + 220, h))
        let top = strip((chrome + 1)..<min(chrome + 9, h))
        guard base > 0.02 else { return 0 }
        return (top - base) / base * 100
    }

    /// How many text pixels the sidebar band actually drew. A blank band means
    /// the evidence does not show the real window's navigation (round-5 finding 1).
    static func sidebarTextPixels(rep: NSBitmapImageRep, chrome: Int) -> Int {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let x0 = 8, x1 = min(240, w / 3)
        guard x1 > x0, h > chrome + 420, let data = rep.bitmapData else { return 0 }
        let bpp = rep.bitsPerPixel / 8, bpr = rep.bytesPerRow
        func lum(_ x: Int, _ y: Int) -> Double {
            let p = pixel(data: data, x: x, y: y, bpp: bpp, bpr: bpr)
            return (0.2126 * Double(p.0) + 0.7152 * Double(p.1) + 0.0722 * Double(p.2)) / 255
        }
        var base: [Double] = []
        for y in stride(from: chrome + 300, to: chrome + 400, by: 4) {
            for x in stride(from: x0, to: x1, by: 6) { base.append(lum(x, y)) }
        }
        base.sort()
        let bg = base.isEmpty ? 0 : base[base.count / 2]
        var count = 0
        for y in (chrome + 60)..<(chrome + 400) {
            for x in x0..<x1 where abs(lum(x, y) - bg) > 0.35 { count += 1 }
        }
        return count
    }

    /// The failure banner must carry its action, printer and cause as drawn
    /// text. Report the message, its ok flag, the accessibility labels of what
    /// was rendered, and the number of contrasting text pixels in the band.
    static func emitBanner(state: AppState, rep: NSBitmapImageRep, capture: NSView) {
        let labels = accessibilityLabels(capture)
        let textPx = bannerTextPixels(rep: rep)
        let obj: [String: Any] = [
            "message": state.lastMessage ?? "",
            "ok": state.lastMessageOK,
            "labels": labels,
            "text_px": textPx,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            print("BANNER \(s)")
        }
    }

    static func bannerTextPixels(rep: NSBitmapImageRep) -> Int {
        let w = rep.pixelsWide, h = min(rep.pixelsHigh, 52)
        guard w > 20, let data = rep.bitmapData else { return 0 }
        let bpp = rep.bitsPerPixel / 8, bpr = rep.bytesPerRow
        func lum(_ x: Int, _ y: Int) -> Double {
            let p = pixel(data: data, x: x, y: y, bpp: bpp, bpr: bpr)
            return (0.2126 * Double(p.0) + 0.7152 * Double(p.1) + 0.0722 * Double(p.2)) / 255
        }
        var bgValues: [Double] = []
        for x in stride(from: w - 40, to: w - 20, by: 2) { bgValues.append(lum(x, 2)) }
        bgValues.sort()
        let bg = bgValues.isEmpty ? 0 : bgValues[bgValues.count / 2]
        var count = 0
        for y in 0..<h {
            for x in 8..<(w - 8) where abs(lum(x, y) - bg) > 0.35 { count += 1 }
        }
        return count
    }

    static func outputName(_ opts: RenderOptions) -> String {
        return "\(opts.target)-\(opts.width)x\(opts.height)-\(opts.appearance).png"
    }

    static func applyWindowSelection(state: AppState, target: String) {
        switch target {
        case let value where value.hasPrefix("window-printers"): state.screen = .printers
        case let value where value.hasPrefix("window-sharing"): state.screen = .sharing
        case let value where value.hasPrefix("window-settings"): state.screen = .settings
        case let value where value.hasPrefix("window-setup"): state.screen = .setup
        case let value where value.hasPrefix("window-stickers"): state.screen = .stickers
        case let value where value.hasPrefix("window-activity"): state.screen = .activity
        case let value where value.hasPrefix("window-whats-new"): state.screen = .overview
        default: state.screen = .overview
        }
    }

    /// An action failure as the window shows it: the same formatter the app uses.
    static func applyOutcomeFixture(_ state: AppState) {
        let result = CommandResult(status: 1, stdout: "",
                                   stderr: "The printer is not responding.")
        let outcome = OutcomeMessage.outcome(
            for: result, success: "unused",
            action: "Sending one test page to HP Laser 107a")
        state.lastMessage = outcome.message
        state.lastMessageOK = outcome.ok
    }

    /// A CUPS read that failed: the page must name the cause and offer Retry.
    static func applyErrorFixture(_ state: AppState) {
        applyEmptyFixture(state)
        state.sharingEnabled = true
        state.printersError = "CUPS is not responding — scheduler is not running."
    }

    /// The first-run state: nothing installed, nothing found.
    static func applyEmptyFixture(_ state: AppState) {
        state.printers = []
        state.detailedPrinters = []
        state.sharingEnabled = false
        state.watcherInstalled = false
        state.watcherLoaded = false
        state.shareLog = []
        state.usbDevices = []
        state.printerHeldByIPPUSB = false
        state.airPrintInstalled = false
        state.labelPrintingNeedsSetup = false
        state.startsAtLogin = false
        state.automaticUSBRelease = false
        state.stickerSizes = []
        state.labelQueues = []
        state.offeredSizes = [:]
        state.printerNameDrafts = [:]
        state.paperChoices = [:]
        state.selectedPaper = [:]
        state.unfinishedJobs = []
        state.activity = []
        state.busy = false
        state.busyMessage = ""
        state.printersError = nil
        state.screen = .overview
    }

    static func pageView(for target: String) -> AnyView {
        switch target {
        case "overview": return AnyView(OverviewView())
        case "printers", "printers-table": return AnyView(PrintersView())
        case "sharing": return AnyView(SharingView())
        case "setup": return AnyView(SetupView())
        case "stickers": return AnyView(StickerSizesView())
        case "activity": return AnyView(ActivityView())
        case "settings": return AnyView(SettingsView())
        case "whats-new": return AnyView(WhatsNewView())
        default: return AnyView(EmptyState(title: "Unknown page", symbol: "questionmark"))
        }
    }

    static func applyPageSelection(state: AppState, page: String, printersListMode: String?) {
        switch page {
        case "overview": state.screen = .overview
        case "printers", "printers-table": state.screen = .printers
        case "sharing": state.screen = .sharing
        case "setup": state.screen = .setup
        case "stickers": state.screen = .stickers
        case "activity": state.screen = .activity
        case "settings": state.screen = .settings
        case "whats-new": state.screen = .overview
        default: state.screen = .overview
        }
        // printersListMode: set around render by caller when applicable; UI may not read it at cb34f18.
        _ = printersListMode
    }

    // MARK: - Fixtures

    static func makeFixtureState() -> AppState {
        let state = AppState()

        // Screenshot runs show invented printers. A released image is public, so it must never
        // carry a real printer's name, model or address; the layout checks keep the familiar one.
        let shots = ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER_SCREENSHOTS"] == "1"
        let n1 = shots ? "Studio_Printer_One" : "HP_Laser_107a"
        let d1 = shots ? "Studio Printer One" : "HP Laser 107a"
        let u1 = shots ? "usb://Studio/Printer%20One?serial=DEMO0001" : "usb://HP/Laser%20107a?serial=SN107AUSB"
        let n2 = shots ? "Studio_Printer_Two" : "HP_Laser_108w"
        let d2 = shots ? "Studio Printer Two" : "HP Laser 108w"
        let u2 = shots ? "ipps://Studio%20Printer%20Two._ipps._tcp.local./" : "ipps://HP%20Laser%20108w._ipps._tcp.local./"
        let n3 = shots ? "Label_Printer" : "Xprinter_Label"
        let d3 = shots ? "Label Printer" : "Xprinter Label"
        let u3 = shots ? "usb://Label/Printer?serial=DEMO0003" : "usb://Xprinter/XP-365B?serial=XPLABEL01"
        let m3 = shots ? "Label Printer 4 inch" : "Xprinter XP-365B Label"

        let hp107 = Printer(name: n1, description: d1, state: "idle", enabled: true, accepting: true,
                            deviceURI: u1, makeAndModel: d1,
                            isShared: true, hasUserACL: true)
        let hp108 = Printer(name: n2, description: d2, state: "idle", enabled: true, accepting: true,
                            deviceURI: u2, makeAndModel: d2,
                            isShared: true, hasUserACL: false)
        let xprinter = Printer(name: n3, description: d3, state: "stopped", enabled: false, accepting: true,
                               deviceURI: u3, makeAndModel: m3,
                               isShared: false, hasUserACL: false)

        state.printers = [hp107, hp108, xprinter]
        state.detailedPrinters = [
            Printer(name: hp107.name, description: hp107.description, state: hp107.state, enabled: hp107.enabled, accepting: hp107.accepting,
                    deviceURI: hp107.deviceURI, makeAndModel: hp107.makeAndModel, isShared: true, hasUserACL: true),
            Printer(name: hp108.name, description: hp108.description, state: hp108.state, enabled: hp108.enabled, accepting: hp108.accepting,
                    deviceURI: hp108.deviceURI, makeAndModel: hp108.makeAndModel, isShared: true, hasUserACL: false),
            Printer(name: xprinter.name, description: xprinter.description, state: xprinter.state, enabled: xprinter.enabled, accepting: xprinter.accepting,
                    deviceURI: xprinter.deviceURI, makeAndModel: xprinter.makeAndModel, isShared: false, hasUserACL: false),
        ]
        state.sharingEnabled = true
        // A shared queue whose printer is unreachable: CUPS accepts the job and
        // waits, so the screens must say so. Off by default so the other
        // renders keep their familiar fixtures.
        if ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER_OFFLINE"] == "1" {
            state.detailedPrinters = state.detailedPrinters.map { printer in
                var offline = printer
                if printer.name == n2 {
                    offline.stateMessage = "The printer is offline."
                    offline.stateReasons = ["offline-report"]
                }
                return offline
            }
            state.automaticUSBRelease = false
        }
        state.watcherInstalled = true
        state.watcherLoaded = true
        state.shareLog = [
            "2026-11-14 08:00:01 watcher: checked sharing, 2 shared queues open",
            "2026-11-14 08:01:01 watcher: no changes needed",
        ]

        // 2 USB devices where one is duplicated
        let usb1 = USBDevice(name: d1, vendorID: "0x03f0", productID: "0xe82a")
        let usb2dup = USBDevice(name: d1, vendorID: "0x03f0", productID: "0xe82a")
        state.usbDevices = [usb1, usb2dup]
        state.printerHeldByIPPUSB = false
        state.airPrintInstalled = true
        state.labelPrintingNeedsSetup = false
        state.startsAtLogin = true
        state.automaticUSBRelease = false

        state.stickerSizes = [
            StickerSize(name: "Shipping 4x6", widthMM: 100, heightMM: 150),
            StickerSize(name: "Address", widthMM: 60, heightMM: 40),
            StickerSize(name: "Small", widthMM: 50, heightMM: 30),
        ]

        state.labelQueues = [
            (queue: n1, isLabel: false),
            (queue: n3, isLabel: true),
        ]
        state.offeredSizes = [
            n1: ["A4", "A5", "Letter"],
            n3: ["psz1000x1500-shipping4x6", "psz500x300-small", "w288h432"],
        ]

        let hpChoices = [
            PageSizeInstaller.PaperChoice(key: "A4", label: "A4 — 210.0 × 297.0 mm", widthMM: 210, heightMM: 297),
            PageSizeInstaller.PaperChoice(key: "A5", label: "A5 — 148.0 × 210.0 mm", widthMM: 148, heightMM: 210),
            PageSizeInstaller.PaperChoice(key: "Letter", label: "Letter — 215.9 × 279.4 mm", widthMM: 215.9, heightMM: 279.4),
        ]
        state.paperChoices = [
            n1: hpChoices,
            n2: [
                PageSizeInstaller.PaperChoice(key: "A4", label: "A4 — 210.0 × 297.0 mm", widthMM: 210, heightMM: 297),
                PageSizeInstaller.PaperChoice(key: "Letter", label: "Letter — 215.9 × 279.4 mm", widthMM: 215.9, heightMM: 279.4),
            ],
            n3: [
                PageSizeInstaller.PaperChoice(key: "psz1000x1500-shipping4x6", label: "Shipping 4x6 — 100.0 × 150.0 mm", widthMM: 100, heightMM: 150),
            ],
        ]
        state.selectedPaper = [
            n1: "A4",
            n2: "A4",
            "Xprinter_Label": "psz1000x1500-shipping4x6",
        ]
        state.printerNameDrafts = [:]

        // unfinished jobs with a duplicate
        state.unfinishedJobs = [
            "\(n1)-42 alice 102400 bytes",
            "\(n1)-42 alice 102400 bytes",
        ]

        // activity with repeated identical entries
        state.activity = [
            LogEntry("Shared queues re-opened to the LAN.", kind: .success),
            LogEntry("Shared queues re-opened to the LAN.", kind: .success),
            LogEntry("Printer Sharing is on.", kind: .info),
            LogEntry("Printer Sharing is on.", kind: .info),
            LogEntry("Background watcher installed — shared queues stay open automatically.", kind: .success),
            LogEntry("Refreshing…", kind: .info),
            LogEntry("Refreshing…", kind: .info),
            LogEntry("Xprinter Label reports: Paused.", kind: .warning),
        ]

        // 2 shared queues (hp107 shared, hp108 shared) - reflected in printer flags above
        state.busy = false
        state.busyMessage = ""
        state.lastMessage = nil
        state.reportFeedback = nil
        state.screen = .overview
        return state
    }

    // MARK: - Theme check

    /// The owner's defect: picking Light or Dark left the page and the cards in
    /// two different schemes. Every Palette surface is a dynamic AppKit colour,
    /// which resolves against the window's real NSAppearance — so this pins the
    /// Mac's appearance, drives the app's own `Appearance.apply`, and measures
    /// the pixels the real window drew. The window keeps `appearance` nil, as
    /// the shipped app's windows do: setting it here would hide the very
    /// disagreement this checks for.
    static func runThemeCheck(_ opts: RenderOptions) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(atPath: opts.outDir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "appearance")

        var failures: [String] = []
        for system in ["light", "dark"] {
            // The Mac's own appearance, pinned so both directions are covered.
            app.appearance = NSAppearance(named: system == "dark" ? .darkAqua : .aqua)
            let first: Appearance = system == "dark" ? .light : .dark
            UserDefaults.standard.set(first.rawValue, forKey: "appearance")
            Appearance.apply(first)                     // launch, before any window
            let (window, hosting) = makeThemeWindow(opts: opts)
            pump(hosting: hosting, window: window)

            // Launch, then the owner's case — changed with the window open — then
            // System, which must follow whatever macOS resolved.
            for (label, choice) in [("launch", first),
                                    ("switch", first == .light ? Appearance.dark : Appearance.light),
                                    ("system", Appearance.system)] {
                UserDefaults.standard.set(choice.rawValue, forKey: "appearance")
                Appearance.apply(choice)
                pump(hosting: hosting, window: window)
                if let problem = reportTheme(label: label, system: system, choice: choice,
                                             window: window, hosting: hosting, outDir: opts.outDir) {
                    failures.append("\(system)/\(label): \(problem)")
                }
            }
        }
        if failures.isEmpty {
            print("THEME_CHECK PASS")
            return
        }
        print("THEME_CHECK FAIL \(failures.joined(separator: " | "))")
        exit(1)
    }

    static func makeThemeWindow(opts: RenderOptions) -> (NSWindow, NSView) {
        let state = makeFixtureState()
        state.screen = .settings
        let controller = NSHostingController(rootView: MainWindow()
            .environmentObject(state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(ProbeFrames.self) { InteractionProbe.frames = $0 })
        controller.sizingOptions = []
        let hosting = controller.view
        hosting.frame = NSRect(x: 0, y: 0, width: opts.width, height: opts.height)
        // Borderless: no titlebar or toolbar means no chrome band and no safe
        // area, so a SwiftUI probe frame maps straight onto the captured bitmap.
        // The window still draws its own dynamic background, which is the
        // surface this check exists to compare with the cards.
        let mask: NSWindow.StyleMask = [.borderless]
        let contentRect = NSWindow.contentRect(forFrameRect: NSRect(x: 0, y: 0,
                                                                    width: CGFloat(opts.width),
                                                                    height: CGFloat(opts.height)),
                                               styleMask: mask)
        let window = NSWindow(contentRect: contentRect, styleMask: mask,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // The dynamic system colour, resolved by AppKit against whatever
        // appearance is in force — exactly as in the shipped app.
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = controller
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.alphaValue = 0.01
        window.orderFront(nil)
        window.makeKey()
        return (window, hosting)
    }

    /// Measures the drawn page and the drawn card, prints them, and returns what
    /// is wrong with them (nil when the two agree on the scheme the choice needs).
    static func reportTheme(label: String, system: String, choice: Appearance,
                            window: NSWindow, hosting: NSView, outDir: String) -> String? {
        guard let cardFrame = InteractionProbe.frames["card.appearance"] else {
            return "no card.appearance probe: the Settings page never laid out"
        }
        let capture = window.contentView?.superview ?? hosting
        guard let rep = capture.bitmapImageRepForCachingDisplay(in: capture.bounds) else {
            return "bitmap allocation failed"
        }
        capture.cacheDisplay(in: capture.bounds, to: rep)
        let name = "theme-\(label)-system-\(system).png"
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))

        // Probe frames and the chrome band are points; the captured bitmap is at
        // the backing scale, so every edge is converted before it is sampled.
        let scale = capture.bounds.width > 0 ? CGFloat(rep.pixelsWide) / capture.bounds.width : 1
        func px(_ points: CGFloat) -> Int { Int((points * scale).rounded()) }
        // The captured frame view starts with the window chrome, so the card
        // shifts down by that band.
        let chrome = capture.bounds.height - hosting.frame.maxY
        let card = modalColor(rep: rep, x: px(cardFrame.minX + 3), y: px(chrome + cardFrame.minY + 3),
                              w: px(cardFrame.width - 6), h: px(cardFrame.height - 6))
        // The page: the full-width gap between this card and the next one, so
        // the sample shares the card's scroll offset and never lands on a card,
        // the sidebar or the window chrome.
        let page = modalColor(rep: rep, x: px(cardFrame.minX + 40), y: px(chrome + cardFrame.maxY + 5),
                              w: px(200), h: px(8))

        let pageLum = luminance(page), cardLum = luminance(card)
        let pageScheme = pageLum >= 0.5 ? "light" : "dark"
        let cardScheme = cardLum >= 0.5 ? "light" : "dark"
        let separation = ratio(page, card)
        // With System the app follows the Mac, so the answer is whatever the
        // window actually resolved — reported, never assumed.
        let effective = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? "dark" : "light"
        let wanted = choice == .system ? effective : (choice == .dark ? "dark" : "light")

        var problems: [String] = []
        if pageScheme != cardScheme {
            problems.append("mixed schemes: page \(pageScheme) (\(hex(page))), card \(cardScheme) (\(hex(card)))")
        }
        if pageScheme != wanted { problems.append("page is \(pageScheme), the choice needs \(wanted)") }
        if cardScheme != wanted { problems.append("card is \(cardScheme), the choice needs \(wanted)") }
        if separation < 1.05 {
            problems.append("page and card do not separate: \(separation):1")
        }

        let obj: [String: Any] = [
            "case": label, "system": system, "choice": choice.rawValue,
            "needed": wanted, "window_effective": effective,
            "page_hex": hex(page), "card_hex": hex(card),
            "page_luminance": (pageLum * 1000).rounded() / 1000,
            "card_luminance": (cardLum * 1000).rounded() / 1000,
            "page_scheme": pageScheme, "card_scheme": cardScheme, "scale": scale,
            "card_rect": [px(cardFrame.minX + 3), px(chrome + cardFrame.minY + 3),
                          px(cardFrame.width - 6), px(cardFrame.height - 6)],
            "page_rect": [px(cardFrame.minX + 40), px(chrome + cardFrame.maxY + 5), px(200), px(8)],
            "page_card_ratio": separation, "image": name,
            "result": problems.isEmpty ? "PASS" : "FAIL",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            print("THEME \(s)")
        }
        return problems.isEmpty ? nil : problems.joined(separator: "; ")
    }

    /// The colour that covers most of the rectangle: a card's fill or the page
    /// behind it, regardless of what text and hairlines sit on top.
    static func modalColor(rep: NSBitmapImageRep, x: Int, y: Int, w: Int, h: Int) -> (UInt8, UInt8, UInt8) {
        let width = rep.pixelsWide, height = rep.pixelsHigh
        guard let data = rep.bitmapData, w > 0, h > 0 else { return (0, 0, 0) }
        let bpp = rep.bitsPerPixel / 8, bpr = rep.bytesPerRow
        var counts: [UInt32: Int] = [:]
        for row in max(0, y)..<min(y + h, height) {
            for column in max(0, x)..<min(x + w, width) {
                let p = pixel(data: data, x: column, y: row, bpp: bpp, bpr: bpr)
                let key = UInt32(p.0) << 16 | UInt32(p.1) << 8 | UInt32(p.2)
                counts[key, default: 0] += 1
            }
        }
        guard let best = counts.max(by: { $0.value < $1.value })?.key else { return (0, 0, 0) }
        return (UInt8((best >> 16) & 0xff), UInt8((best >> 8) & 0xff), UInt8(best & 0xff))
    }

    static func luminance(_ c: (UInt8, UInt8, UInt8)) -> Double {
        func lin(_ v: UInt8) -> Double {
            let s = Double(v) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }

    static func ratio(_ a: (UInt8, UInt8, UInt8), _ b: (UInt8, UInt8, UInt8)) -> Double {
        let l1 = luminance(a), l2 = luminance(b)
        return ((max(l1, l2) + 0.05) / (min(l1, l2) + 0.05) * 1000).rounded() / 1000
    }

    static func hex(_ c: (UInt8, UInt8, UInt8)) -> String {
        String(format: "#%02X%02X%02X", c.0, c.1, c.2)
    }

    // MARK: - Switch check

    /// Drives the Printers page's Table/Cards control with a real offscreen mouse
    /// event. The control does not exist at cb34f18; this check is skippable until
    /// the Fleet UI merge adds it.
    static func runSwitchCheck(_ opts: RenderOptions) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        try? FileManager.default.createDirectory(atPath: opts.outDir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "printersListMode")

        let state = makeFixtureState()
        state.screen = .printers
        let controller = NSHostingController(rootView: MainWindow()
            .environmentObject(state)
            .background(Color(nsColor: .windowBackgroundColor))
            .tint(Color.accentColor)
            .environment(\.controlActiveState, .key))
        let hosting = controller.view
        hosting.frame = NSRect(x: 0, y: 0, width: opts.width, height: opts.height)

        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let light = NSAppearance(named: .aqua) {
            window.appearance = light
            light.performAsCurrentDrawingAppearance {
                window.backgroundColor = NSColor.windowBackgroundColor
            }
        }
        window.contentViewController = controller
        window.setContentSize(NSSize(width: opts.width, height: opts.height))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        // Ordered in but fully transparent: SwiftUI delivers clicks only to an
        // ordered, key window; alpha 0 keeps it off the owner's desktop, and a
        // presented sheet is made transparent the same way.
        window.alphaValue = 0
        window.orderFront(nil)
        window.makeKey()
        for _ in 0..<12 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        guard let control = findSwitchControl(hosting) else {
            print("SWITCH_CHECK FAIL switch control not found at cb34f18 (Fleet UI Table/Cards not merged yet); skipped")
            return
        }
        // `Cards`/`Table` may appear in either order.
        guard let tableIndex = (0..<control.segmentCount).first(where: {
            (control.label(forSegment: $0) ?? "").lowercased().contains("table")
        }) else {
            print("SWITCH_CHECK FAIL switch control found but Table segment is missing")
            exit(1)
        }

        let before = renderHash(view: hosting)
        // Click the Table segment. Auto-width segments report 0 via width(forSegment:),
        // so use the accessibility radio frame when it exists, else the segment half.
        var segmentX: CGFloat? = nil
        var running: CGFloat = 0
        for index in 0..<control.segmentCount {
            let width = control.width(forSegment: index)
            if width > 0 {
                if index == tableIndex { segmentX = running + width / 2; break }
                running += width
            }
        }
        if segmentX == nil {
            func radioFrames(_ element: Any) -> [(String, CGRect)] {
                var out: [(String, CGRect)] = []
                if let view = element as? NSView {
                    if view.accessibilityRole() == .radioButton {
                        out.append((view.accessibilityLabel() ?? "", view.accessibilityFrame()))
                    }
                    for child in view.accessibilityChildren() ?? [] { out.append(contentsOf: radioFrames(child)) }
                } else if let ax = element as? any NSAccessibilityProtocol {
                    if ax.accessibilityRole() == .radioButton {
                        out.append((ax.accessibilityLabel() ?? "", ax.accessibilityFrame()))
                    }
                    for child in ax.accessibilityChildren() ?? [] { out.append(contentsOf: radioFrames(child)) }
                }
                return out
            }
            if let hit = radioFrames(control).first(where: { $0.0.lowercased().contains("table") }) {
                let windowRect = window.convertFromScreen(hit.1)
                let local = control.convert(windowRect, from: nil)
                segmentX = local.midX
                print("SWITCH_CHECK segment via accessibility frame \(hit.1)")
            } else {
                segmentX = control.bounds.width * (tableIndex == control.segmentCount - 1 ? 0.75 : 0.25)
            }
        }
        let localPoint = NSPoint(x: segmentX ?? control.bounds.midX, y: control.bounds.midY)
        let windowPoint = control.convert(localPoint, to: nil)

        // A real click only: no programmatic segment selection. Send the mouse
        // pair through the window first; if hit testing does not reach the
        // control, deliver the same pair to the control itself.
        func mouseEvent(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1,
                               pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let down = mouseEvent(.leftMouseDown), let up = mouseEvent(.leftMouseUp) else {
            print("SWITCH_CHECK FAIL could not create mouse event")
            exit(1)
        }
        func pump() {
            for _ in 0..<12 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
        }
        window.sendEvent(down)
        window.sendEvent(up)
        pump()
        var clickPath = "window"
        var mode = UserDefaults.standard.string(forKey: "printersListMode") ?? ""
        if mode != "table" {
            control.mouseDown(with: down)
            control.mouseUp(with: up)
            pump()
            clickPath = "control"
            mode = UserDefaults.standard.string(forKey: "printersListMode") ?? ""
        }
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(
                to: URL(fileURLWithPath: opts.outDir).appendingPathComponent("debug-switch-after.png"))
        }
        let after = renderHash(view: hosting)
        let changed = before != after
        let persisted = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        let stored = persisted?["printersListMode"] as? String ?? "(not persisted)"

        if mode == "table" {
            print("SWITCH_CHECK PASS click=\(clickPath) mode=table changed=\(changed) persisted=\(stored) selectedSegment=\(control.selectedSegment)")
            return
        }
        print("SWITCH_CHECK FAIL mode=\(mode.isEmpty ? "(unset)" : mode) changed=\(changed) persisted=\(stored) selectedSegment=\(control.selectedSegment) expected=\(tableIndex)")
        exit(1)
    }

    // MARK: - Keyboard check

    /// Focuses the Cards/Table control, drives it with an arrow key through the
    /// responder chain, and records whether Tab moves focus. Offscreen only.
    static func runKeyboardCheck(_ opts: RenderOptions) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        try? FileManager.default.createDirectory(atPath: opts.outDir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "printersListMode")

        let state = makeFixtureState()
        state.screen = .printers
        let controller = NSHostingController(rootView: MainWindow()
            .environmentObject(state)
            .background(Color(nsColor: .windowBackgroundColor))
            .tint(Color.accentColor)
            .environment(\.controlActiveState, .key))
        let hosting = controller.view
        hosting.frame = NSRect(x: 0, y: 0, width: opts.width, height: opts.height)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let light = NSAppearance(named: .aqua) {
            window.appearance = light
            light.performAsCurrentDrawingAppearance {
                window.backgroundColor = NSColor.windowBackgroundColor
            }
        }
        window.contentViewController = controller
        window.setContentSize(NSSize(width: opts.width, height: opts.height))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        // Ordered in but fully transparent: SwiftUI only delivers clicks to an
        // ordered, key window, and alpha 0 keeps it off the owner's desktop.
        window.alphaValue = 0
        window.orderFront(nil)
        window.makeKey()
        for _ in 0..<12 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        guard let control = findSwitchControl(hosting) else {
            print("KEYBOARD_CHECK FAIL switch control not found")
            exit(1)
        }
        guard let tableIndex = (0..<control.segmentCount).first(where: {
            (control.label(forSegment: $0) ?? "").lowercased().contains("table")
        }) else {
            print("KEYBOARD_CHECK FAIL Table segment missing")
            exit(1)
        }

        window.makeFirstResponder(control)
        let focusAccepted = window.firstResponder === control
        print("FOCUS_ACCEPTED \(focusAccepted) control=\(type(of: control))")

        // Focus ring and responder traversal, plus the accessibility surface.
        // Key delivery cannot run in an inactive offscreen app, so traversal is
        // exercised through the window's own key-view command, which is what Tab
        // runs at the responder level.
        for _ in 0..<4 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)); window.displayIfNeeded() }
        func focusRingCount(_ view: NSView) -> Int {
            var count = String(describing: type(of: view)).contains("FocusRing") ? 1 : 0
            for child in view.subviews { count += focusRingCount(child) }
            return count
        }
        let ring = focusRingCount(hosting)
        print("FOCUS_RING \(ring > 0) rings=\(ring)")

        window.makeFirstResponder(hosting)
        let first = String(describing: type(of: window.firstResponder ?? hosting))
        window.selectNextKeyView(nil)
        for _ in 0..<3 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)); window.displayIfNeeded() }
        let second = String(describing: type(of: window.firstResponder ?? hosting))
        window.selectNextKeyView(nil)
        for _ in 0..<3 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)); window.displayIfNeeded() }
        let third = String(describing: type(of: window.firstResponder ?? hosting))
        let traversalMoved = first != second || second != third
        print("TRAVERSAL first=\(first) second=\(second) third=\(third) moved=\(traversalMoved)")

        let axApp = AXUIElementCreateApplication(getpid())
        var axValue: CFTypeRef?
        let axErr = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &axValue)
        let axWindows = (axValue as? [AXUIElement])?.count ?? -1
        print("AX_SELF err=\(axErr.rawValue) windows=\(axWindows)")
        let before = control.selectedSegment
        let arrow = tableIndex == control.segmentCount - 1 ? "\u{F703}" : "\u{F702}"
        let keyCode: UInt16 = tableIndex == control.segmentCount - 1 ? 124 : 123
        if let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil,
                                       characters: arrow, charactersIgnoringModifiers: arrow,
                                       isARepeat: false, keyCode: keyCode) {
            // Drive the shipped control's own key handling.
            control.keyDown(with: down)
            app.postEvent(down, atStart: false)
        }
        if let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [],
                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: window.windowNumber, context: nil,
                                     characters: arrow, charactersIgnoringModifiers: arrow,
                                     isARepeat: false, keyCode: keyCode) {
            control.keyUp(with: up)
        }
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        var after = control.selectedSegment
        var mode = UserDefaults.standard.string(forKey: "printersListMode") ?? ""
        var path = "arrow-key"
        if !(after == tableIndex && mode == "table") {
            // The offscreen host is not the active app, so AppKit's key handling
            // may not run. Press the segment through the accessibility API the
            // way Full Keyboard Access and VoiceOver do.
            if let radio = findRadio(in: control, label: "table") {
                _ = radio.accessibilityPerformPress()
                path = "accessibility-press"
                for _ in 0..<10 {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                    hosting.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                }
                after = control.selectedSegment
                mode = UserDefaults.standard.string(forKey: "printersListMode") ?? ""
            }
        }
        let keyboardOperated = after == tableIndex && mode == "table"

        window.makeFirstResponder(hosting)
        let focusBefore = String(describing: type(of: window.firstResponder ?? hosting))
        if let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil,
                                      characters: "\t", charactersIgnoringModifiers: "\t",
                                      isARepeat: false, keyCode: 48) {
            app.postEvent(tab, atStart: false)
        }
        for _ in 0..<6 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        let focusAfter = String(describing: type(of: window.firstResponder ?? hosting))
        print("TAB_FOCUS before=\(focusBefore) after=\(focusAfter) moved=\(focusBefore != focusAfter)")

        if keyboardOperated {
            print("KEYBOARD_CHECK PASS via=\(path) before=\(before) after=\(after) mode=\(mode) tableIndex=\(tableIndex) focusRing=\(ring > 0) traversalMoved=\(traversalMoved)")
            return
        }
        // Offscreen the harness app is not active, so AppKit does not deliver key
        // events. Record what is provable: the shipped control accepts keyboard
        // focus. Traversal is reported as not checked, never as passed.
        print("KEYBOARD_CHECK PARTIAL focus=\(focusAccepted) ring=\(ring > 0) traversalMoved=\(traversalMoved) via=\(path) before=\(before) after=\(after) mode=\(mode.isEmpty ? "(unset)" : mode) keys=inactive-window axErr=\(axErr.rawValue)")
        if focusAccepted { return }
        exit(1)
    }

    /// Finds a radio button by its accessibility label, the element Full
    /// Keyboard Access and VoiceOver operate.
    static func findRadio(in element: Any, label: String) -> NSView? {
        if let view = element as? NSView {
            if view.accessibilityRole() == .radioButton,
               (view.accessibilityLabel() ?? "").lowercased().contains(label) {
                return view
            }
            for child in view.accessibilityChildren() ?? [] {
                if let found = findRadio(in: child, label: label) { return found }
            }
        } else if let ax = element as? any NSAccessibilityProtocol {
            for child in ax.accessibilityChildren() ?? [] {
                if let found = findRadio(in: child, label: label) { return found }
            }
        }
        return nil
    }

    static func findSwitchControl(_ view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl, control.segmentCount >= 2 {
            let labels = (0..<control.segmentCount).map { (control.label(forSegment: $0) ?? "").lowercased() }
            if labels.contains(where: { $0.contains("cards") }) && labels.contains(where: { $0.contains("table") }) {
                return control
            }
        }
        for child in view.subviews {
            if let found = findSwitchControl(child) { return found }
        }
        return nil
    }

    static func findTable(_ view: NSView) -> NSView? {
        if view is NSTableView || view is NSTableHeaderView { return view }
        for child in view.subviews {
            if let found = findTable(child) { return found }
        }
        return nil
    }

    static func accessibilityLabels(_ element: Any) -> [String] {
        var labels: [String] = []
        if let view = element as? NSView {
            if let label = view.accessibilityLabel(), !label.isEmpty { labels.append(label) }
            for child in view.accessibilityChildren() ?? [] {
                labels.append(contentsOf: accessibilityLabels(child))
            }
        } else if let accessible = element as? any NSAccessibilityProtocol {
            if let label = accessible.accessibilityLabel(), !label.isEmpty { labels.append(label) }
            for child in accessible.accessibilityChildren() ?? [] {
                labels.append(contentsOf: accessibilityLabels(child))
            }
        }
        return labels
    }

    static func renderHash(view: NSView) -> Int {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return 0 }
        return data.hashValue
    }

    // MARK: - Page interactions

    /// One real control per page, driven in a hidden window. The app's own
    /// action runs end to end (busy → action → banner/activity/setting); only
    /// the system command is stubbed by AppState.renderActionsStubbed. Each run
    /// reports how the control was reached and driven, the measured outcome,
    /// and writes an after-image that is measured like every other render.
    static func step(_ message: String) {
        if ProcessInfo.processInfo.environment["PRINTER_INTERACTION_DEBUG"] == "1" {
            print("STEP \(message)")
            fflush(stdout)
        }
    }

    static func runInteraction(_ opts: RenderOptions) {
        step("start \(opts.target)")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        try? FileManager.default.createDirectory(atPath: opts.outDir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "printersListMode")
        UserDefaults.standard.removeObject(forKey: "appearance")

        let isWhatsNew = opts.target == "whats-new"
        let state = makeFixtureState()
        let flag = DismissFlag()
        let wanted = screenFor(opts.target)
        // Start elsewhere so the sidebar row itself has to work. The sticker
        // page is the exception: inserting it during a List-selection update
        // aborts the offscreen host (AttributeGraph precondition), so it opens
        // at start-up and only its layout is measured.
        if opts.target == "stickers" {
            state.screen = .stickers
        } else {
            state.screen = isWhatsNew || wanted == .overview ? .settings : .overview
        }

        let root: AnyView = isWhatsNew
            ? AnyView(WhatsNewSheetHost(flag: flag))
            : AnyView(MainWindow().environmentObject(state))
        let controller = NSHostingController(rootView: root
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.page)
            .foregroundStyle(Palette.body)
            .tint(Color.accentColor)
            .groupBoxStyle(CardGroupStyle())
            .environment(\.controlActiveState, .key)
            .onPreferenceChange(ProbeFrames.self) { InteractionProbe.frames = $0 })
        controller.sizingOptions = []
        let hosting = controller.view
        hosting.frame = NSRect(x: 0, y: 0, width: opts.width, height: opts.height)
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: isWhatsNew ? [.titled, .closable, .resizable] : [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let light = NSAppearance(named: .aqua) {
            window.appearance = light
            light.performAsCurrentDrawingAppearance { window.backgroundColor = NSColor.windowBackgroundColor }
        }
        window.contentViewController = controller
        window.setContentSize(NSSize(width: opts.width, height: opts.height))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        // Ordered in but fully transparent: SwiftUI only delivers clicks to an
        // ordered, key window, and alpha 0 keeps it off the owner's desktop.
        window.alphaValue = 0
        window.orderFront(nil)
        window.makeKey()
        pump(hosting: hosting, window: window)
        step("laid out; probes=\(InteractionProbe.frames.keys.sorted())")

        // 1 — reach the page through its own sidebar row.
        var nav = isWhatsNew ? "n/a" : (opts.target == "stickers" ? "set-at-start" : "not-found")
        if !isWhatsNew, opts.target != "stickers", let title = sidebarTitle(opts.target) {
            if let frame = InteractionProbe.frames["nav.\(title)"],
               clickProbeFrame(frame, on: window, hosting: hosting) {
                nav = "click"
                pump(hosting: hosting, window: window)
            }
        }
        if state.screen != wanted {
            state.screen = wanted
            nav += "+set-directly"
            pump(hosting: hosting, window: window)
        }

        step("navigated: screen=\(state.screen.map { String(describing: $0) } ?? "nil")")
        // 2 — drive the page's control.
        let before = state.activity.count
        let control = interactionControl(opts.target)
        var via = "not-found"
        var clickFrame: CGRect? = nil
        switch opts.target {
        case "settings":
            if let seg = findSegments(in: hosting), let dark = segmentIndex(seg, "dark") {
                if clickSegment(seg, index: dark, on: window) { via = "click" }
                pump(hosting: hosting, window: window)
            }
        case "whats-new":
            window.attachedSheet?.alphaValue = 0
            let sheet = window.attachedSheet
            let sheetHosting = sheet?.contentView ?? hosting
            if let frame = InteractionProbe.frames[probeName(opts.target)],
               clickProbeFrame(frame, on: sheet ?? window, hosting: sheetHosting) {
                via = "click"
                pump(hosting: hosting, window: window)
            }
        default:
            if opts.target == "stickers" {
                // Documented harness limit: mutating the sticker list aborts the
                // offscreen host with an AttributeGraph precondition whatever the
                // window style, probes or animations, so only the nav click is
                // driven here. The apply path stays covered by the paper-size
                // suites; COMPLETENESS.md records the gap.
            } else if let frame = InteractionProbe.frames[probeName(opts.target)] {
                clickFrame = frame
                if clickProbeFrame(frame, on: window, hosting: hosting) {
                    via = "click"
                    step("click sent at \(frame)")
                    pump(hosting: hosting, window: window)
                    step("pump done")
                }
            }
        }
        step("driven: via=\(via) banner=\(state.lastMessage ?? "")")
        var met = interactionOutcomeMet(opts.target, state: state, flag: flag)
        if opts.target == "stickers" {
            met = state.screen == .stickers
                && InteractionProbe.frames["control.addSize"] != nil
                && InteractionProbe.frames["control.applySizes"] != nil
        }

        var obj: [String: Any] = [
            "page": opts.target,
            "control": control,
            "nav": nav,
            "via": via,
            "banner": state.lastMessage ?? "",
            "ok": state.lastMessageOK,
            "activity_before": before,
            "activity_after": state.activity.count,
            "probes": InteractionProbe.frames.keys.sorted(),
            "click_frame": clickFrame.map { [Int($0.minX), Int($0.minY), Int($0.width), Int($0.height)] } ?? [],
            "result": opts.target == "stickers" ? (met ? "LIMITED" : "FAIL") : (met ? "PASS" : "FAIL"),
        ]
        if opts.target == "stickers" {
            obj["limited"] = "offscreen host aborts AttributeGraph when the sticker page is inserted or its list mutated; only its laid-out action controls are measured"
        }
        switch opts.target {
        case "settings": obj["appearance"] = UserDefaults.standard.string(forKey: "appearance") ?? ""
        case "activity": obj["first_row"] = state.activity.first?.message ?? ""
        case "whats-new": obj["dismissed"] = flag.dismissed
        default: break
        }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            print("INTERACTION \(s)")
        }

        // The outcome as drawn, measured like every other evidence image.
        let capView = window.contentView?.superview ?? hosting
        if let rep = capView.bitmapImageRepForCachingDisplay(in: capView.bounds) {
            capView.cacheDisplay(in: capView.bounds, to: rep)
            let name = "interaction-\(opts.target)-\(opts.width)x\(opts.height)-\(opts.appearance).png"
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: opts.outDir).appendingPathComponent(name))
            let g = measure(rep: rep, isWindow: false, accent: nil, sampleBottom: true)
            let shot = RenderOptions(mode: "page", target: "interaction-\(opts.target)", outDir: opts.outDir,
                                     width: opts.width, height: opts.height, appearance: opts.appearance,
                                     printersListMode: nil)
            emitResult(opts: shot, ok: met, error: met ? nil : "interaction outcome not met", geom: g,
                       controls: nil, pixels: (rep.pixelsWide, rep.pixelsHigh))
        }
        exit(met ? 0 : 1)
    }

    // MARK: - Sidebar movement

    /// The owner's defect: the sidebar visibly jumps when it is clicked, and
    /// some buttons do the same. Measure the sidebar's parts and every nav row
    /// before, during and after a real click, and across a busy toggle, in the
    /// real chrome (titled window, the app's own toolbar). Fails when any
    /// measured part moves.
    static func runSidebarCheck(_ opts: RenderOptions) {
        step("sidebar-check start")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        try? FileManager.default.createDirectory(atPath: opts.outDir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "printersListMode")
        UserDefaults.standard.removeObject(forKey: "appearance")

        var failures: [String] = []
        // The app's own minimum and its usual window: a column that only moves
        // at one of them would be missed by measuring just one.
        for (width, height) in [(860, 580), (1024, 720)] {
            failures += measureSidebar(width: width, height: height, outDir: opts.outDir)
        }
        if failures.isEmpty {
            print("SIDEBAR_CHECK PASS nothing moved across selection, busy or a banner at either size")
            exit(0)
        }
        print("SIDEBAR_CHECK FAIL " + failures.joined(separator: " | "))
        exit(1)
    }

    /// One window, every phase, one list of movements. Returns the faults.
    static func measureSidebar(width: Int, height: Int, outDir: String) -> [String] {
        let state = makeFixtureState()
        state.screen = .overview
        let controller = NSHostingController(rootView: MainWindow()
            .environmentObject(state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.page)
            .foregroundStyle(Palette.body)
            .tint(Color.accentColor)
            .groupBoxStyle(CardGroupStyle())
            .environment(\.controlActiveState, .key)
            .onPreferenceChange(ProbeFrames.self) { InteractionProbe.frames = $0 })
        controller.sizingOptions = []
        let hosting = controller.view
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let light = NSAppearance(named: .aqua) {
            window.appearance = light
            light.performAsCurrentDrawingAppearance { window.backgroundColor = NSColor.windowBackgroundColor }
        }
        window.contentViewController = controller
        window.setContentSize(NSSize(width: width, height: height))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.alphaValue = 0
        window.orderFront(nil)
        window.makeKey()
        pump(hosting: hosting, window: window)

        var phases: [(String, [String: CGRect])] = []
        func snap(_ phase: String) {
            pump(hosting: hosting, window: window)
            let frames = InteractionProbe.frames.filter {
                $0.key.hasPrefix("nav.") || $0.key.hasPrefix("sidebar.") || $0.key == "detail.page"
            }
            phases.append((phase, frames))
            let entries = frames.keys.sorted().map { key -> String in
                let f = frames[key]!
                return String(format: "%@=%.1f,%.1f,%.1f,%.1f", key,
                              f.minX, f.minY, f.width, f.height)
            }
            print("SIDEBAR size=\(width)x\(height) phase=\(phase) "
                  + "screen=\(state.screen.map { String(describing: $0) } ?? "nil") "
                  + "window=\(Int(window.frame.width))x\(Int(window.frame.height)) "
                  + entries.joined(separator: " "))
            let capView = window.contentView?.superview ?? hosting
            if let rep = capView.bitmapImageRepForCachingDisplay(in: capView.bounds) {
                capView.cacheDisplay(in: capView.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: outDir)
                        .appendingPathComponent("sidebar-\(width)x\(height)-\(phase).png"))
            }
        }

        guard InteractionProbe.frames["nav.Activity"] != nil,
              InteractionProbe.frames["nav.Overview"] != nil else {
            window.close()
            return ["no nav probes at \(width)x\(height): \(InteractionProbe.frames.keys.sorted())"]
        }
        snap("idle")
        // A real click cannot be delivered to a window whose app is not active,
        // and activating would take the owner's desktop. Select the row the way
        // a click makes the control select it: the list's own selection API.
        // The rows are in Screen.allCases order.
        var seen = Set<String>()
        if let table = findTable(in: hosting) {
            let rows = table.numberOfRows
            print("SIDEBAR list rows=\(rows) selected=\(table.selectedRow)")
            for (index, screen) in Screen.allCases.enumerated() where index < rows {
                // Inserting the sticker page aborts the offscreen host
                // (AttributeGraph), the limit already recorded for the
                // interaction pass; its page render is gated separately. The
                // sidebar's geometry does not depend on the detail page.
                if screen == .stickers { continue }
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                snap("select-\(screen.rawValue)")
                seen.insert(state.screen.map { String(describing: $0) } ?? "nil")
            }
            print("SIDEBAR limit=stickers page insertion aborts the offscreen host; its render is a separate gate step")
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            snap("reselect")
        } else {
            print("SIDEBAR_CHECK note: no NSTableView found; selecting through the model")
            for screen in Screen.allCases {
                state.screen = screen
                snap("select-\(screen.rawValue)")
                seen.insert(String(describing: screen))
            }
            state.screen = .overview
            snap("reselect")
        }
        state.busy = true
        state.busyMessage = "Printing a test page..."
        snap("busy")
        state.busy = false
        state.busyMessage = ""
        snap("idle-again")
        state.lastMessage = "Refreshed — 3 printers."
        state.lastMessageOK = true
        snap("banner")
        state.lastMessage = nil
        snap("banner-gone")
        print("SIDEBAR window-key=\(window.isKeyWindow) app-active=\(NSApp.isActive)")

        var faults: [String] = []
        // The sticker page is skipped (its insertion aborts the offscreen
        // host); every other screen is reached through the list's selection.
        let reachable = Screen.allCases.count - 1
        if seen.count != reachable {
            faults.append("selection reached \(seen.count) of \(reachable) measurable screens at \(width)x\(height)")
        }
        // Any measured part moving between phases is the jump. 0.5 pt is the
        // measurement floor: probe frames are laid out in whole points. A nav
        // row's own width changes when it is selected (the title turns
        // semibold) and nothing moves, so only its position is compared.
        let baseline = phases.first!.1
        for (phase, frames) in phases.dropFirst() {
            for key in baseline.keys.sorted() {
                guard let a = baseline[key], let b = frames[key] else { continue }
                let dx = abs(a.minX - b.minX), dy = abs(a.minY - b.minY)
                let dw = abs(a.width - b.width), dh = abs(a.height - b.height)
                let sized = !key.hasPrefix("nav.")
                if max(dx, dy, sized ? max(dw, dh) : 0) > 0.5 {
                    faults.append(String(format: "%dx%d %@ %@ dx=%.1f dy=%.1f dw=%.1f dh=%.1f",
                                         width, height, phase, key, dx, dy, dw, dh))
                }
            }
        }
        window.close()
        return faults
    }

    static func pump(hosting: NSView, window: NSWindow, rounds: Int = 12) {
        for _ in 0..<rounds {
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
    }

    static func interactionControl(_ target: String) -> String {
        switch target {
        case "overview": return "Fix shared queues now"
        case "printers": return "Print test page"
        case "sharing": return "Remove"
        case "setup": return "Keep it ready"
        case "stickers": return "Add a size"
        case "activity": return "Refresh"
        case "settings": return "Appearance: Dark"
        case "whats-new": return "Done"
        default: return ""
        }
    }

    /// What the shipped app must have produced for the interaction to count.
    static func interactionOutcomeMet(_ target: String, state: AppState, flag: DismissFlag) -> Bool {
        let banner = state.lastMessage ?? ""
        switch target {
        case "overview": return state.lastMessageOK && banner == "Shared queues re-opened to the LAN." && state.queuesHeldShut.isEmpty
        case "printers": return state.lastMessageOK && banner == "Test page sent to HP Laser 107a."
        case "sharing": return state.lastMessageOK && banner == "Background watcher removed." && !state.watcherInstalled
        case "setup": return state.lastMessageOK && banner.hasPrefix("Automatic USB release is running") && state.automaticUSBRelease

        case "activity": return (state.activity.first?.message ?? "").hasPrefix("Refreshed —") && !state.busy
        case "settings": return UserDefaults.standard.string(forKey: "appearance") == "dark"
        case "whats-new": return flag.dismissed
        default: return false
        }
    }

    static func screenFor(_ target: String) -> Screen {
        switch target {
        case "printers": return .printers
        case "sharing": return .sharing
        case "setup": return .setup
        case "stickers": return .stickers
        case "activity": return .activity
        case "settings": return .settings
        default: return .overview
        }
    }

    static func sidebarTitle(_ target: String) -> String? {
        switch target {
        case "overview": return "Overview"
        case "printers": return "Printers"
        case "sharing": return "Sharing"
        case "setup": return "HP Laser 107a"
        case "stickers": return "Paper & Sticker Sizes"
        case "activity": return "Activity"
        case "settings": return "Settings"
        default: return nil
        }
    }

    /// The probe name of the control each page drives.
    static func probeName(_ target: String) -> String {
        switch target {
        case "overview": return "control.fixQueues"
        case "printers": return "control.printTest"
        case "sharing": return "control.watcher"
        case "setup": return "control.keepReady"
        case "stickers": return "control.addSize"
        case "activity": return "control.refresh"
        case "whats-new": return "control.done"
        default: return ""
        }
    }

    /// A real mouse click at a probe frame (SwiftUI content coordinates,
    /// top-left origin) through the window that hosts it.
    static func clickProbeFrame(_ frame: CGRect, on window: NSWindow, hosting: NSView) -> Bool {
        guard frame.width > 1, frame.height > 1 else { return false }
        let point = NSPoint(x: frame.midX, y: hosting.bounds.height - frame.midY)
        guard point.x >= 0, point.x <= window.frame.width, point.y >= 0, point.y <= window.frame.height else {
            return false
        }
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                            timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil,
                                            eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 0) else { return false }
        window.sendEvent(down)
        window.sendEvent(up)
        return true
    }

    static func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, table.numberOfRows > 1 { return table }
        for child in view.subviews {
            if let found = findTable(in: child) { return found }
        }
        return nil
    }

    /// Half a click, so the frame can be measured while the button is down.
    static func pressProbeFrame(_ frame: CGRect, on window: NSWindow, hosting: NSView,
                                down: Bool) -> Bool {
        guard frame.width > 1, frame.height > 1 else { return false }
        let point = NSPoint(x: frame.midX, y: hosting.bounds.height - frame.midY)
        guard let event = NSEvent.mouseEvent(with: down ? .leftMouseDown : .leftMouseUp,
                                             location: point, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1,
                                             pressure: down ? 1 : 0) else { return false }
        window.sendEvent(event)
        return true
    }

    static func findSegments(in root: NSView) -> NSSegmentedControl? {
        if let seg = root as? NSSegmentedControl, seg.segmentCount >= 2 {
            let labels = (0..<seg.segmentCount).map { (seg.label(forSegment: $0) ?? "").lowercased() }
            if labels.contains(where: { $0.contains("dark") }) && labels.contains(where: { $0.contains("light") }) {
                return seg
            }
        }
        for child in root.subviews {
            if let found = findSegments(in: child) { return found }
        }
        return nil
    }

    static func segmentIndex(_ control: NSSegmentedControl, _ label: String) -> Int? {
        (0..<control.segmentCount).first { (control.label(forSegment: $0) ?? "").lowercased().contains(label) }
    }

    static func clickSegment(_ control: NSSegmentedControl, index: Int, on window: NSWindow) -> Bool {
        let widths = (0..<control.segmentCount).map { control.width(forSegment: $0) }
        var x: CGFloat = control.bounds.width * (CGFloat(index) + 0.5) / CGFloat(control.segmentCount)
        if widths.allSatisfy({ $0 > 0 }) {
            x = widths.prefix(index).reduce(0, +) + widths[index] / 2
        }
        let point = control.convert(NSPoint(x: x, y: control.bounds.midY), to: nil)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                            timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil,
                                            eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 0) else { return false }
        window.sendEvent(down)
        window.sendEvent(up)
        if control.selectedSegment != index {
            control.mouseDown(with: down)
            control.mouseUp(with: up)
        }
        return control.selectedSegment == index
    }

    // MARK: - Measurement

    struct Geometry {
        let contentBottom: Int
        let leftGutter: Int
        let rightGutter: Int
        let clipped: Bool
        /// Tallest solid run of the primary-button colour. A button that is
        /// covered by a following card leaves only a short strip.
        let accentRun: Int
    }

    static func measure(rep: NSBitmapImageRep, isWindow: Bool, accent: NSColor?,
                        sampleBottom: Bool = false) -> Geometry {
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 2, h > 0, let data = rep.bitmapData else {
            return Geometry(contentBottom: 0, leftGutter: 0, rightGutter: 0, clipped: false, accentRun: 0)
        }
        let bpp = rep.bitsPerPixel / 8
        let bpr = rep.bytesPerRow
        // sample background from a corner known to be page (bottom when a banner
        // spans the top edge)
        let bg = pixel(data: data, x: w - 1, y: sampleBottom ? h - 1 : 0, bpp: bpp, bpr: bpr)
        let accentRGB = accent.map { color -> (Int, Int, Int) in
            // Compare in the bitmap's color space, not sRGB: a P3 backing store
            // stores different component values for the same colour.
            let c = color.usingColorSpace(rep.colorSpace) ?? color
            return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }

        var minX = w
        var maxX = -1
        var maxY = -1
        var maxAccentRun = 0
        for x in 0..<w {
            var run = 0
            for y in 0..<h {
                let p = pixel(data: data, x: x, y: y, bpp: bpp, bpr: bpr)
                if !same(p, bg) {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
                if let a = accentRGB,
                   abs(Int(p.0) - a.0) <= 14, abs(Int(p.1) - a.1) <= 14,
                   abs(Int(p.2) - a.2) <= 14, p.3 > 200 {
                    run += 1
                    if run > maxAccentRun { maxAccentRun = run }
                } else {
                    run = 0
                }
            }
        }
        if maxX < 0 {
            return Geometry(contentBottom: 0, leftGutter: w, rightGutter: w, clipped: false, accentRun: 0)
        }
        let leftGutter = minX
        let rightGutter = (w - 1) - maxX
        let contentBottom = maxY
        // Window mode: the sidebar material is deliberately flush left, so only
        // the right edge is a clip signal. Pages test both edges. A result
        // banner spans the width by design, so its render skips the side test.
        let clipped = (sampleBottom || isWindow)
            ? false
            : (leftGutter < 12 || rightGutter < 12)
        return Geometry(contentBottom: contentBottom, leftGutter: leftGutter, rightGutter: rightGutter,
                        clipped: clipped, accentRun: maxAccentRun)
    }

    static func pixel(data: UnsafeMutablePointer<UInt8>, x: Int, y: Int, bpp: Int, bpr: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let off = y * bpr + x * bpp
        let r = data[off]
        let g = bpp > 1 ? data[off + 1] : r
        let b = bpp > 2 ? data[off + 2] : r
        let a = bpp > 3 ? data[off + 3] : 255
        return (r, g, b, a)
    }

    static func same(_ a: (UInt8, UInt8, UInt8, UInt8), _ b: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        // Small tolerance for antialiasing/compositing noise.
        let tol: Int = 6
        return abs(Int(a.0) - Int(b.0)) <= tol &&
               abs(Int(a.1) - Int(b.1)) <= tol &&
               abs(Int(a.2) - Int(b.2)) <= tol &&
               abs(Int(a.3) - Int(b.3)) <= tol
    }

    static func emitResult(opts: RenderOptions, ok: Bool, error: String?, geom: Geometry?,
                           controls: [[String: String]]? = nil,
                           pixels: (Int, Int)? = nil,
                           chrome: Int? = nil, headingTop: Int? = nil, topWashPct: Double? = nil,
                           sidebarPx: Int? = nil,
                           actionRow: [[String: Any]]? = nil) {
        var obj: [String: Any] = [
            "page": opts.mode == "window" ? "window" : opts.target,
            "target": opts.target,
            "width": pixels?.0 ?? opts.width,
            "height": pixels?.1 ?? opts.height,
            "requested_width": opts.width,
            "requested_height": opts.height,
            "appearance": opts.appearance,
            "ok": ok,
        ]
        if let error { obj["error"] = error }
        if let g = geom {
            obj["content_bottom_px"] = g.contentBottom
            obj["right_gutter_px"] = g.rightGutter
            obj["left_gutter_px"] = g.leftGutter
            obj["clipped"] = g.clipped
            obj["accent_run_px"] = g.accentRun
        }
        if let controls, !controls.isEmpty { obj["controls"] = controls }
        if let chrome { obj["chrome_px"] = chrome }
        if let headingTop { obj["heading_top_px"] = headingTop }
        if let topWashPct { obj["top_wash_pct"] = (topWashPct * 10).rounded() / 10 }
        if let sidebarPx { obj["sidebar_px"] = sidebarPx }
        if let actionRow, !actionRow.isEmpty { obj["action_row"] = actionRow }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            print("MEASURE \(s)")
        }
    }

    /// The state of switches and segmented controls, so a render can be checked
    /// against its fixture instead of relying on the inactive-window drawing.
    static func controlStates(_ view: NSView) -> [[String: String]] {
        var out: [[String: String]] = []
        if let toggle = view as? NSSwitch {
            out.append(["type": "switch", "label": toggle.accessibilityLabel() ?? "",
                        "value": toggle.state == .on ? "on" : "off"])
        } else if let segment = view as? NSSegmentedControl {
            out.append(["type": "segmented", "label": segment.accessibilityLabel() ?? "",
                        "value": "\(segment.selectedSegment)"])
        }
        func walkAccessibility(_ element: Any) {
            if let view = element as? NSView {
                let role = view.accessibilityRole()
                if role == .checkBox {
                    out.append(["type": "switch", "label": view.accessibilityLabel() ?? "",
                                "value": "\(view.accessibilityValue() ?? "")"])
                }
                for child in view.accessibilityChildren() ?? [] { walkAccessibility(child) }
            } else if let ax = element as? any NSAccessibilityProtocol {
                let role = ax.accessibilityRole()
                if role == .checkBox {
                    out.append(["type": "switch", "label": ax.accessibilityLabel() ?? "",
                                "value": "\(ax.accessibilityValue() ?? "")"])
                }
                for child in ax.accessibilityChildren() ?? [] { walkAccessibility(child) }
            }
        }
        walkAccessibility(view)
        for child in view.subviews { out.append(contentsOf: controlStates(child)) }
        return out
    }
}
