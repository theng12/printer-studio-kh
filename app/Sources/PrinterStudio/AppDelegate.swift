import SwiftUI
import AppKit

extension Notification.Name {
    /// A reopen from the app icon (Finder, Spotlight, `open`). SwiftUI's `Window`
    /// scene does not bring itself back, and this app has no Dock icon to click.
    static let printerStudioOpenWindow = Notification.Name("PrinterStudioOpenWindow")
}

/// Handles the reopen Apple Event. It is the one route back that SwiftUI leaves
/// unhandled, so the menu-bar label must be listening.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .printerStudioOpenWindow, object: nil)
        return true
    }
}

/// Opens the main window when the app is reopened. A hidden test run stays hidden.
struct ReopenOpensMainWindow: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let hiddenRun: Bool

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .printerStudioOpenWindow)) { _ in
            guard !hiddenRun else { return }
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
    }
}
