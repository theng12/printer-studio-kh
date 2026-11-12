import SwiftUI

/// The Support page behind "Support this app". It never asks for anything: the
/// app is free with every feature unlocked, and the donation is one optional link.
struct SupportView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Support Printer Studio KH").font(.title2.weight(.semibold))
            Text("Printer Studio KH is free, and every feature is unlocked for everyone. Nothing here is required to keep using the app.")
                .fixedSize(horizontal: false, vertical: true)
            Text("If it saved you time, you can leave a one-time donation. It opens in your browser; the app sends no information with it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Open the donation page") { ExternalLinks.open(ExternalLinks.donation) }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 460)
    }
}
