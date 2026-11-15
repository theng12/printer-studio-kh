import Foundation
import SwiftUI
import AppKit

@main
struct TestAppearance {
    static var passed = 0
    static var failed = 0

    static func assertTest(_ condition: Bool, _ name: String) {
        if condition {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ FAIL: \(name)")
        }
    }

    static func main() {
        print("Running Appearance Test Suite…\n")

        assertTest(Appearance.allCases.map(\.title) == ["System", "Light", "Dark"],
                   "Exactly three choices: System, Light, Dark")
        assertTest(Appearance.allCases.map(\.rawValue) == ["system", "light", "dark"],
                   "Stored values are system/light/dark")
        assertTest(Appearance.stored(nil) == .system, "Nothing stored starts on System")
        assertTest(Appearance.stored("system") == .system, "Stored system reads back")
        assertTest(Appearance.stored("light") == .light, "Stored light reads back")
        assertTest(Appearance.stored("dark") == .dark, "Stored dark reads back")
        assertTest(Appearance.stored("default") == .system, "Old Default choice reads as System")
        assertTest(Appearance.stored("nonsense") == .system, "Unknown value falls back to System")
        assertTest(Appearance.system.nsAppearance == nil, "System leaves the appearance to macOS")
        assertTest(Appearance.light.nsAppearance?.name == .aqua, "Light sets the light AppKit appearance")
        assertTest(Appearance.dark.nsAppearance?.name == .darkAqua, "Dark sets the dark AppKit appearance")

        // The stored choice must reach the real appearance, which every Palette
        // surface resolves against. Setting only SwiftUI's colour scheme left
        // the cards and the page in different schemes.
        Appearance.apply(.dark)
        assertTest(NSApplication.shared.appearance?.name == .darkAqua,
                   "Applying Dark sets the app appearance")
        Appearance.apply(.light)
        assertTest(NSApplication.shared.appearance?.name == .aqua,
                   "Applying Light sets the app appearance")
        Appearance.apply(.system)
        assertTest(NSApplication.shared.appearance == nil,
                   "Applying System hands appearance back to macOS")

        print("\nSummary: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
