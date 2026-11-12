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
    case failed(reason: String)
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

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var state: UpdateState = .notChecked

    var statusLine: String {
        switch state {
        case .notChecked: return "Not checked"
        case .checking: return "Checking..."
        case .upToDate: return "Checked just now · up to date"
        case .available(let version): return "Checked just now · \(version) is available"
        case .failed(let reason): return "Check failed: \(reason). Try again."
        }
    }

    var availableVersion: String? {
        if case .available(let version) = state { return version }
        return nil
    }

    private struct Publisher: Decodable {
        let feedURL: URL
        let publicKey: String
        let testAuthority: Bool
    }

    private struct SignedFeed: Decodable {
        let feed: String
        let signature: String
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking

        let publisherURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/KHUpdater/publisher.json")
        guard let publisherData = try? Data(contentsOf: publisherURL),
              let publisher = try? JSONDecoder().decode(Publisher.self, from: publisherData) else {
            state = .failed(reason: "this Mac is not connected to an Update Studio")
            return
        }

        // Info.plist carries the tailnet ATS exception this needs; the signature
        // check below, not the transport, is what makes the feed trustworthy.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
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
        guard let signed = try? JSONDecoder().decode(SignedFeed.self, from: data) else {
            state = .failed(reason: "the update feed is invalid")
            return
        }
        let feed: UpdateFeed
        do {
            feed = try verifiedUpdateFeed(feed: signed.feed, signature: signed.signature, publicKey: publisher.publicKey)
        } catch UpdateCheckError.invalidSignature {
            state = .failed(reason: "the update feed signature could not be verified")
            return
        } catch {
            state = .failed(reason: "the update feed is invalid")
            return
        }
        guard let bundleID = Bundle.main.bundleIdentifier else {
            state = .failed(reason: "this app's bundle identifier is unavailable")
            return
        }
        guard let version = feed.version(for: bundleID) else {
            state = .failed(reason: "this Update Studio does not offer this app")
            return
        }
        guard let offered = KhVersion.parse(version) else {
            state = .failed(reason: "the update feed version is invalid")
            return
        }
        guard let installedString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let installed = KhVersion.parse(installedString) else {
            state = .failed(reason: "this app's installed version is invalid")
            return
        }
        state = offered.isNewer(than: installed) ? .available(version: version) : .upToDate
    }
}
