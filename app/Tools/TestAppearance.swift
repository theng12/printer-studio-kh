import Foundation
import SwiftUI

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
        assertTest(Appearance.system.colorScheme == nil, "System leaves the scheme to macOS")
        assertTest(Appearance.light.colorScheme == .light, "Light forces the light scheme")
        assertTest(Appearance.dark.colorScheme == .dark, "Dark forces the dark scheme")

        print("\nSummary: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
