import Foundation
import CryptoKit

@main
struct TestUpdateChecker {
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

    static func main() throws {
        print("Running Update Checker Test Suite…\n")
        for value in ["", "1.2.3.4.5.6.7", "1.a", "1234567890", "v1.2", "1..2", "١"] {
            assertTest(KhVersion.parse(value) == nil, "Rejects invalid version '\(value)'")
        }
        func newer(_ left: String, _ right: String) -> Bool {
            guard let a = KhVersion.parse(left), let b = KhVersion.parse(right) else { return false }
            return a.isNewer(than: b)
        }
        assertTest(newer("1.10", "1.9"), "Compares numerically")
        assertTest(!newer("1.9", "1.10"), "Older version is not newer")
        assertTest(!newer("1.2", "1.2"), "Equal version is not newer")
        assertTest(!newer("1.2", "1.2.0"), "Missing parts equal zero")
        assertTest(newer("1.2.1", "1.2"), "Nonzero extra part is newer")
        assertTest(newer("2", "1.99.99"), "Earlier parts take precedence")

        let key = Curve25519.Signing.PrivateKey()
        let wrongKey = Curve25519.Signing.PrivateKey()
        let bundleID = "com.example.printer"
        let bytes = Data("{\"schema\":1,\"published_at\":\"now\",\"apps\":{\"internal-id\":{\"bundleID\":\"com.example.printer\",\"version\":\"2.0\"}}}".utf8)
        let signature = try key.signature(for: bytes)
        let encoded = bytes.base64EncodedString()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let feed = try? verifiedUpdateFeed(feed: encoded, signature: signature.base64EncodedString(), publicKey: publicKey)
        assertTest(feed?.version(for: bundleID) == "2.0", "Verifies signed feed and finds bundle ID")
        assertTest(feed?.version(for: "com.example.other") == nil, "Missing bundle ID is not offered")
        var tampered = signature
        tampered[tampered.startIndex] ^= 1
        assertTest((try? verifiedUpdateFeed(feed: encoded, signature: tampered.base64EncodedString(), publicKey: publicKey)) == nil,
                   "Rejects tampered signature")
        assertTest((try? verifiedUpdateFeed(feed: encoded, signature: signature.base64EncodedString(),
                                            publicKey: wrongKey.publicKey.rawRepresentation.base64EncodedString())) == nil,
                   "Rejects wrong public key")
        let badSchema = Data("{\"schema\":2,\"apps\":{}}".utf8)
        let badSchemaSignature = try key.signature(for: badSchema)
        assertTest((try? verifiedUpdateFeed(feed: badSchema.base64EncodedString(), signature: badSchemaSignature.base64EncodedString(),
                                            publicKey: publicKey)) == nil, "Rejects unsupported schema")
        let invalidJSON = Data("not JSON".utf8)
        let invalidSignature = try key.signature(for: invalidJSON)
        assertTest((try? verifiedUpdateFeed(feed: invalidJSON.base64EncodedString(), signature: invalidSignature.base64EncodedString(),
                                            publicKey: publicKey)) == nil, "Rejects signed non-JSON feed")

        // The update key is pinned inside the bundle. This test binary is given
        // the shipped resource by app/test-update-checker.sh.
        let fleetKey = "BXtuZrRgTVcM+MkDukuS725aV2i22hVQIoxG2EIQyn0="
        let keyFile = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
        assertTest(PinnedPublisherKey.value(at: keyFile) == fleetKey,
                   "The shipped PublisherKey.txt is the fleet key")
        assertTest(PinnedPublisherKey.value(at: nil) == nil, "No key URL means no key")
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("printer-pinned-key-\(UUID().uuidString)")
        try Data().write(to: scratch)
        assertTest(PinnedPublisherKey.value(at: scratch) == nil, "An empty key file means no key")
        try Data(("  \(fleetKey)\n").utf8).write(to: scratch)
        assertTest(PinnedPublisherKey.value(at: scratch) == fleetKey, "Stray whitespace around the key is ignored")
        try Data("not a key".utf8).write(to: scratch)
        assertTest(PinnedPublisherKey.value(at: scratch) == nil, "A malformed key file means no key")
        try Data(Data(repeating: 7, count: 31).base64EncodedString().utf8).write(to: scratch)
        assertTest(PinnedPublisherKey.value(at: scratch) == nil, "A 31-byte key is refused")
        try? FileManager.default.removeItem(at: scratch)
        assertTest(PinnedPublisherKey.value(at: scratch) == nil, "A missing key file means no key")

        // What a rewritten publisher.json can and cannot do. It still names the
        // feed; its key is ignored, and a feed signed by that key is refused.
        func envelope(_ feed: Data, _ signed: Data) -> Data {
            Data("{\"feed\":\"\(feed.base64EncodedString())\",\"signature\":\"\(signed.base64EncodedString())\"}".utf8)
        }
        let attackerURL = "http://attacker.example/release.json"
        let attackerFile = Data("""
            {"feedURL":"\(attackerURL)","publicKey":"\(wrongKey.publicKey.rawRepresentation.base64EncodedString())"}
            """.utf8)
        let publisher = PublisherFile.address(attackerFile)
        assertTest(publisher?.feedURL.absoluteString == attackerURL, "A rewritten file still supplies the feed address")
        assertTest(publisher?.publicKey == wrongKey.publicKey.rawRepresentation.base64EncodedString(),
                   "A rewritten file's own key is seen, never used")
        let attackerSigned = try wrongKey.signature(for: bytes)
        assertTest(updateState(feedData: envelope(bytes, attackerSigned), pinnedKey: publicKey,
                               bundleID: bundleID, installed: "1.0")
                   == .failed(reason: "the update was refused because it was not signed by this app's key"),
                   "A feed signed by the key the file names is refused")
        assertTest(updateState(feedData: envelope(bytes, signature), pinnedKey: publicKey,
                               bundleID: bundleID, installed: "1.0") == .available(version: "2.0"),
                   "A feed signed by the pinned key is accepted even when the file named another")
        assertTest(updateState(feedData: envelope(bytes, signature), pinnedKey: publicKey,
                               bundleID: bundleID, installed: "2.0") == .upToDate,
                   "The same pinned feed offers nothing on an installed 2.0")
        assertTest(updateState(feedData: envelope(bytes, signature), pinnedKey: nil,
                               bundleID: bundleID, installed: "1.0") == .missingKey,
                   "No pinned key stops the check instead of using the file's key")

        print("\nSummary: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
