import AppKit

/// The only web addresses this app may send someone to. Everything else in the
/// app opens a local file or nothing at all, so a link that did not come from
/// here cannot take over the browser.
enum ExternalLinks {
    static let donation = URL(string: "https://nowpayments.io/donation/studiokh")!

    private static let allowedHosts: Set<String> = ["nowpayments.io"]

    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host, allowedHosts.contains(host) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
