import AppKit
import SwiftUI

/// The app's surface ramp, status colours and one accent.
///
/// Surface values are SwiftUI semantic colours, so Light and Dark follow macOS.
/// The opacity steps below are measured, not eyeballed: body ink over the
/// window background gives the page, and a measured fraction of body ink gives
/// the muted text.
///
/// Status and accent are explicit pairs because the system green/orange/red are
/// too light for small light-mode text on white (measured 2.0–3.5:1). Each has a
/// dark light-mode variant for text and a bright dark-mode variant; the filled
/// primary button uses `accentFill`, which carries white text at >= 4.5:1 in
/// both appearances.
enum Palette {
    /// Body text.
    static let body = Color(nsColor: .labelColor)
    /// The window background with 9% body ink over it: one measured step away
    /// from `surface`, so cards read as a layer (1.19:1 Light, 1.25:1 Dark).
    static let page = body.opacity(0.09)
    /// Cards and groups, one step above the page.
    static let surface = Color(nsColor: .controlBackgroundColor)
    /// Hairlines and quiet card outlines (1.24:1 Light, 1.36:1 Dark on page).
    static let border = Color(nsColor: .separatorColor)
    /// Supporting text: body ink at 66%, measured 4.71:1 Light and 5.32:1 Dark
    /// on the page, 4.92:1 and 6.06:1 on the surface.
    static let muted = body.opacity(0.66)

    /// Links, icons and text accents: >= 4.5:1 on the page in both appearances.
    static let accent = pair("PrinterAccent", light: (0.00, 0.35, 0.78), dark: (0.44, 0.70, 1.00))
    /// Filled primary buttons: white text >= 4.5:1 in both appearances.
    static let accentFill = pair("PrinterAccentFill", light: (0.00, 0.35, 0.78), dark: (0.12, 0.44, 0.88))
    /// State text on a 15% tint of itself or on the page/surface.
    static let success = pair("PrinterSuccess", light: (0.00, 0.42, 0.20), dark: (0.30, 0.85, 0.55))
    static let warning = pair("PrinterWarning", light: (0.55, 0.30, 0.00), dark: (1.00, 0.68, 0.25))
    static let danger = pair("PrinterDanger", light: (0.68, 0.10, 0.08), dark: (1.00, 0.42, 0.38))

    private static func pair(_ name: String, light: (CGFloat, CGFloat, CGFloat),
                             dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
