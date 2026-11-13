import AppKit
import SwiftUI

/// The app's surface ramp and status colours.
///
/// Every value is a SwiftUI semantic colour, so Light and Dark follow macOS.
/// The opacity steps below are measured, not eyeballed: body ink over the
/// window background gives the page, and a measured fraction of body ink gives
/// the muted text.
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

    /// The one accent, for primary actions and selection.
    static let accent = Color.accentColor
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
}
