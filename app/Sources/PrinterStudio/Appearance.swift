import SwiftUI

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

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    /// Reads the stored choice. An older build offered a "Default" option that
    /// behaved as System, so a value from then keeps working as System instead
    /// of silently resetting to a different look.
    static func stored(_ raw: String?) -> Appearance {
        Appearance(rawValue: raw ?? "") ?? .system
    }
}
