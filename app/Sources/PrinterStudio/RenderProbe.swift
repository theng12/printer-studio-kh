import SwiftUI

// A no-op in the shipped app. Under the offscreen render harness
// (PRINTER_STUDIO_RENDER=1) `.probe(name)` reports the control's laid-out frame
// so the interaction pass can click the real control and the window pass can
// measure where the page heading actually sits. Nothing here touches state,
// drawing or behaviour when the harness is not running.

enum InteractionProbe {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER"] == "1"
    }

    static var frames: [String: CGRect] = [:]
}

struct ProbeFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ProbeAnchor: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        if InteractionProbe.enabled {
            content.background(GeometryReader { proxy in
                Color.clear.preference(key: ProbeFrames.self, value: [name: proxy.frame(in: .global)])
            })
        } else {
            content
        }
    }
}

extension View {
    func probe(_ name: String) -> some View {
        modifier(ProbeAnchor(name: name))
    }
}
