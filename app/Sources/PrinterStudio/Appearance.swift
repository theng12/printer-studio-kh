import SwiftUI
import AppKit

/// The app's appearance choice. System is the starting value for a new install
/// and for anyone who has never picked explicitly.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The real AppKit appearance. Every surface in Palette is a dynamic AppKit
    /// colour, and those resolve against the window's actual NSAppearance, so
    /// this — not SwiftUI's colour scheme — is what decides how the app draws.
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    /// The one owner of the app's appearance: called at launch and on every
    /// change. System passes nil, so macOS keeps following itself, live.
    static func apply(_ appearance: Appearance) {
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    /// Reads the stored choice. An older build offered a "Default" option that
    /// behaved as System, so a value from then keeps working as System instead
    /// of silently resetting to a different look.
    static func stored(_ raw: String?) -> Appearance {
        Appearance(rawValue: raw ?? "") ?? .system
    }
}
