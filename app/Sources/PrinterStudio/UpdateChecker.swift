import Foundation
import Combine
import CryptoKit

/// Brings the one updater forward. Installing stays there: this app never
/// downloads, verifies or replaces itself.
enum UpdaterHandoff {
    static func open() {
        _ = Shell.run("/usr/bin/open", ["-b", "com.khupdater.launcher"])
    }
}

enum UpdateState: Equatable {
    case notChecked
    case checking
    case upToDate
    case available(version: String)
    /// The appcast's newest item. Worded so it never promises what Sparkle may decline.
    case offered(version: String)
    case failed(reason: String)

    /// Fail closed: no pinned key, no update check. Never the file's key instead.
    static let missingKey = UpdateState.failed(
        reason: "this app cannot check for updates because its built-in update key is missing")
}

struct KhVersion {
    private let parts: [Int]

    static func parse(_ value: String) -> KhVersion? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...6).contains(parts.count), parts.allSatisfy({ part in
            (1...9).contains(part.utf8.count) && part.utf8.allSatisfy { (48...57).contains($0) }
        }) else { return nil }
        return KhVersion(parts: parts.map { Int($0)! })
    }

    func isNewer(than other: KhVersion) -> Bool {
        for index in 0..<max(parts.count, other.parts.count) {
            let left = index < parts.count ? parts[index] : 0
            let right = index < other.parts.count ? other.parts[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}

struct UpdateFeed: Decodable {
    struct App: Decodable {
        let bundleID: String
        let version: String
    }
    let schema: Int
    let apps: [String: App]

    func version(for bundleID: String) -> String? {
        apps.values.first { $0.bundleID == bundleID }?.version
    }
}

enum UpdateCheckError: Error {
    case invalidSignature
    case invalidFeed
}

func verifiedUpdateFeed(feed: String, signature: String, publicKey: String) throws -> UpdateFeed {
    guard let bytes = Data(base64Encoded: feed),
          let signatureBytes = Data(base64Encoded: signature),
          let keyBytes = Data(base64Encoded: publicKey),
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes),
          key.isValidSignature(signatureBytes, for: bytes) else {
        throw UpdateCheckError.invalidSignature
    }
    guard let decoded = try? JSONDecoder().decode(UpdateFeed.self, from: bytes), decoded.schema == 1 else {
        throw UpdateCheckError.invalidFeed
    }
    return decoded
}

/// `~/Library/KHUpdater/publisher.json` may name the feed. It may not name the
/// key: anything running as the logged-in user can rewrite that file, so a key
/// found there is read to be noticed, then ignored.
struct PublisherFile: Decodable {
    let feedURL: URL
    let publicKey: String?

    static func address(_ data: Data) -> PublisherFile? {
        try? JSONDecoder().decode(PublisherFile.self, from: data)
    }
}

/// The fleet publisher key, shipped at Contents/Resources/PublisherKey.txt and
/// covered by the app's own signature. Nil means this build lost it.
enum PinnedPublisherKey {
    static func value(at url: URL?) -> String? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let key = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              Data(base64Encoded: key)?.count == 32 else { return nil }
        return key
    }

    static func bundleValue(_ bundle: Bundle = .main) -> String? {
        value(at: bundle.url(forResource: "PublisherKey", withExtension: "txt"))
    }
}

private struct SignedFeed: Decodable {
    let feed: String
    let signature: String
}

/// Everything after the feed's bytes are in hand. Only the pinned key verifies
/// a feed; whatever key the publisher file named never reaches this.
func updateState(feedData: Data, pinnedKey: String?, bundleID: String?, installed: String?) -> UpdateState {
    guard let pinnedKey else { return .missingKey }
    guard let signed = try? JSONDecoder().decode(SignedFeed.self, from: feedData) else {
        return .failed(reason: "the update feed is invalid")
    }
    let feed: UpdateFeed
    do {
        feed = try verifiedUpdateFeed(feed: signed.feed, signature: signed.signature, publicKey: pinnedKey)
    } catch UpdateCheckError.invalidSignature {
        return .failed(reason: "the update was refused because it was not signed by this app's key")
    } catch {
        return .failed(reason: "the update feed is invalid")
    }
    guard let bundleID else { return .failed(reason: "this app's bundle identifier is unavailable") }
    guard let version = feed.version(for: bundleID) else {
        return .failed(reason: "this Update Studio does not offer this app")
    }
    guard let offered = KhVersion.parse(version) else {
        return .failed(reason: "the update feed version is invalid")
    }
    guard let installed, let installedVersion = KhVersion.parse(installed) else {
        return .failed(reason: "this app's installed version is invalid")
    }
    return offered.isNewer(than: installedVersion) ? .available(version: version) : .upToDate
}

/// The newest item in the app's own appcast — the feed Sparkle installs from.
/// Deliberately narrow: it reads the version strings and nothing else, because
/// Sparkle is what verifies the signature and decides whether this Mac can take it.
func appcastOfferedVersion(_ data: Data) -> String? {
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    var newest: (String, KhVersion)?
    var search = text[...]
    while let open = search.range(of: "<item>"), let close = search.range(of: "</item>", range: open.upperBound..<search.endIndex) {
        let item = search[open.upperBound..<close.lowerBound]
        if let start = item.range(of: "<sparkle:shortVersionString>"),
           let end = item.range(of: "</sparkle:shortVersionString>", range: start.upperBound..<item.endIndex) {
            let version = String(item[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = KhVersion.parse(version), newest.map({ parsed.isNewer(than: $0.1) }) ?? true {
                newest = (version, parsed)
            }
        }
        search = search[close.upperBound...]
    }
    return newest?.0
}

/// What the pressable check reports when the appcast is the source of truth.
func appcastState(appcastData: Data, installed: String?) -> UpdateState {
    guard let offeredVersion = appcastOfferedVersion(appcastData) else {
        return .failed(reason: "the update feed has no version in it")
    }
    guard let offered = KhVersion.parse(offeredVersion) else {
        return .failed(reason: "the update feed version is invalid")
    }
    guard let installed, let installedVersion = KhVersion.parse(installed) else {
        return .failed(reason: "this app's installed version is invalid")
    }
    return offered.isNewer(than: installedVersion) ? .offered(version: offeredVersion) : .upToDate
}

/// How long ago the last finished check was, in words: "just now", "5 min ago",
/// "1 hr 30 min ago", "2 days ago". A stored verdict must never read as live.
func checkedAge(since lastChecked: Date, now: Date) -> String {
    let minutes = Int(now.timeIntervalSince(lastChecked)) / 60
    guard minutes >= 1 else { return "just now" }
    if minutes < 60 { return "\(minutes) min ago" }
    let hours = minutes / 60
    if hours < 24 {
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr ago" : "\(hours) hr \(rest) min ago"
    }
    let days = hours / 24
    return days == 1 ? "1 day ago" : "\(days) days ago"
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var state: UpdateState = .notChecked
    /// When the last check finished, so the footer can say how old its answer is.
    private(set) var lastChecked: Date?

    func statusLine(at now: Date) -> String {
        let age = checkedAge(since: lastChecked ?? now, now: now)
        switch state {
        case .notChecked: return "Not checked"
        case .checking: return "Checking..."
        case .upToDate: return "Checked \(age) · up to date"
        case .available(let version): return "Checked \(age) · \(version) is available"
        case .offered(let version): return "Checked \(age) · \(version) is offered; it installs the next time the app starts"
        case .failed(let reason): return "Check failed: \(reason). Try again."
        }
    }

    var availableVersion: String? {
        if case .available(let version) = state { return version }
        return nil
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking
        defer { if state != .checking { lastChecked = Date() } }

        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        // The app's own appcast is the feed Sparkle installs from. Asking it here
        // means the sentence on screen is about the update this app will actually take.
        if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           let feedURL = URL(string: feed) {
            let data: Data
            do {
                let (responseData, response) = try await session.data(from: feedURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    state = .failed(reason: "the update feed could not be reached (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))")
                    return
                }
                data = responseData
            } catch {
                state = .failed(reason: "the update feed could not be reached (\(error.localizedDescription))")
                return
            }
            state = appcastState(appcastData: data, installed: installed)
            return
        }

        // No appcast address in the bundle: fall back to the signed KH feed, if this Mac has one.
        guard let pinnedKey = PinnedPublisherKey.bundleValue() else {
            state = .missingKey
            return
        }
        let publisherURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/KHUpdater/publisher.json")
        guard let publisherData = try? Data(contentsOf: publisherURL),
              let publisher = PublisherFile.address(publisherData) else {
            state = .failed(reason: "this app has no update feed to check")
            return
        }
        if let named = publisher.publicKey, named != pinnedKey {
            NSLog("Printer Studio KH: publisher.json names a different update key; only the key built into this app is used.")
        }

        // Info.plist carries the tailnet ATS exception this needs; the pinned key, not
        // the transport, is what makes a signed KH feed trustworthy.
        let data: Data
        do {
            let (responseData, response) = try await session.data(from: publisher.feedURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                state = .failed(reason: "the update feed could not be reached")
                return
            }
            data = responseData
        } catch {
            state = .failed(reason: "the update feed could not be reached")
            return
        }
        state = updateState(feedData: data,
                            pinnedKey: pinnedKey,
                            bundleID: Bundle.main.bundleIdentifier,
                            installed: installed)
    }
}
