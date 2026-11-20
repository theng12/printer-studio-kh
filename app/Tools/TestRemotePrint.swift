import Foundation

/// The four controls, driven without a socket: the switch, the three token
/// refusals, the content rule and the kill switch.
@main
struct TestRemotePrint {
    static func main() {
        // Every run uses its own support directory, so the owner's store is untouched.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("remote-print-test-\(UUID().uuidString)", isDirectory: true)
        setenv("PRINTER_STUDIO_TEST_DATA_DIR", root.path, 1)

        func request(_ method: String, _ path: String, token: String? = nil, body: String = "") -> (Int, [String: Any]) {
            var head = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\n"
            if let token { head += "X-Device-Token: \(token)\r\n" }
            let bytes = Data(body.utf8)
            head += "Content-Length: \(bytes.count)\r\n\r\n"
            var data = Data(head.utf8); data.append(bytes)
            let (status, response) = RemotePrint.route(method: method, path: path, request: data)
            let object = (try? JSONSerialization.jsonObject(with: response)) as? [String: Any] ?? [:]
            return (status, object)
        }

        // 1. Off by default: nothing answers, even with a token.
        UserDefaults.standard.set(false, forKey: RemotePrint.enabledKey)
        var (status, object) = request("GET", "/api/remote/content")
        precondition(status == 403, "feature off must be refused")
        precondition(object["error"] as? String == "feature_off", "feature off must name itself")
        print("PASS: off by default — feature_off, \(status)")

        UserDefaults.standard.set(true, forKey: RemotePrint.enabledKey)

        // 2. Three distinct token refusals.
        (status, object) = request("GET", "/api/remote/content")
        precondition(status == 401 && object["error"] as? String == "missing_token", "missing token")
        print("PASS: no token — missing_token, \(status)")

        (status, object) = request("GET", "/api/remote/content", token: "not-a-token")
        precondition(status == 401 && object["error"] as? String == "wrong_token", "wrong token")
        print("PASS: wrong token — wrong_token, \(status)")

        guard let minted = RemotePrint.mint(name: "Test laptop") else { preconditionFailure("mint failed") }
        precondition(RemotePrint.devices().count == 1, "device stored")
        precondition(!RemotePrint.devices()[0].tokenHash.contains(minted.token), "raw token never stored")
        let fileMode = (try? FileManager.default.attributesOfItem(atPath: RemotePrint.devicesURL.path))?[.posixPermissions] as? NSNumber
        precondition(fileMode?.intValue == 0o600, "device store is 0600, was \(String(describing: fileMode))")
        print("PASS: mint stores a hash only, file 0600")

        (status, object) = request("GET", "/api/remote/content", token: minted.token)
        precondition(status == 200, "valid token answers, got \(status) \(object)")
        let content = object["content"] as? [[String: Any]] ?? []
        precondition(content.contains { $0["id"] as? String == "test-page" }, "test page is listed")
        print("PASS: valid token lists content (\(content.count) item(s))")

        RemotePrint.revoke(id: minted.device.id)
        (status, object) = request("GET", "/api/remote/content", token: minted.token)
        precondition(status == 401 && object["error"] as? String == "revoked_token", "revoked token")
        print("PASS: revoked token — revoked_token, \(status)")

        // 3. Content rule: a path, URL or file is refused by name.
        guard let second = RemotePrint.mint(name: "Second device") else { preconditionFailure("mint failed") }
        for body in ["{\"path\":\"/etc/passwd\"}", "{\"url\":\"https://example.com/a.pdf\"}",
                     "{\"file\":\"report.pdf\"}", "{\"document\":\"x\"}"] {
            (status, object) = request("POST", "/api/remote/print", token: second.token, body: body)
            precondition(status == 403 && object["error"] as? String == "content_not_allowed",
                         "\(body) must be refused by name")
        }
        print("PASS: path / url / file / document refused by name")

        (status, object) = request("POST", "/api/remote/print", token: second.token,
                                   body: "{\"content\":\"something-else\"}")
        precondition(status == 404 && object["error"] as? String == "unknown_content", "unknown id")
        print("PASS: unknown id — unknown_content, \(status)")

        // Every refusal is audited with the device and the rule.
        let jobs = RemotePrint.jobs()
        precondition(jobs.count >= 6, "each refusal recorded, got \(jobs.count)")
        precondition(jobs.contains { $0.outcome == .refused && $0.detail == "content_not_allowed" }, "audit names the rule")
        print("PASS: audit records each attempt (\(jobs.count) lines)")

        // 4. Kill switch: the very next request is refused, no restart.
        RemotePrint.revokeAll()
        (status, object) = request("GET", "/api/remote/content", token: second.token)
        precondition(status == 401 && object["error"] as? String == "revoked_token", "kill switch immediate")
        print("PASS: kill switch — next request revoked_token, \(status)")

        // A fresh token after the kill switch still works, so the switch revokes, it does not break minting.
        guard let third = RemotePrint.mint(name: "After kill switch") else { preconditionFailure("mint failed") }
        (status, _) = request("GET", "/api/remote/content", token: third.token)
        precondition(status == 200, "minting works after the kill switch")
        print("PASS: a new token works after the kill switch")

        // Turning it off removes the tailnet mapping, read back from Tailscale
        // itself rather than trusting the app's own line.
        if let cli = RemotePrint.cliPath() {
            let enable = RemotePrint.setEnabled(true)
            if enable.ok {
                let on = shell(cli, ["serve", "status"])
                precondition(on.contains("\(RemotePrint.servePort)"),
                             "serve status does not name \(RemotePrint.servePort) while on: \(on)")
                print("PASS: switch on — tailscale serve status names \(RemotePrint.servePort)")
                precondition(RemotePrint.setEnabled(false).ok, "switch off failed")
                let after = shell(cli, ["serve", "status"])
                precondition(!after.contains("\(RemotePrint.servePort)"),
                             "the mapping survived switch off: \(after)")
                print("PASS: switch off — tailscale serve status no longer names \(RemotePrint.servePort)")
            } else {
                print("SKIP: serve could not be applied here: \(enable.combined.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        } else {
            print("SKIP: no Tailscale CLI found; enabling refuses by name")
        }

        UserDefaults.standard.set(false, forKey: RemotePrint.enabledKey)
        try? FileManager.default.removeItem(at: root)
    }

    static func shell(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
