import Foundation
import CryptoKit

// MARK: - Records

struct RemoteDevice: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// SHA-256 of the token. The token itself is shown once and never stored.
    var tokenHash: String
    var createdAt: Date
    var revokedAt: Date?
    var lastUsedAt: Date?
    var isRevoked: Bool { revokedAt != nil }
}

struct RemoteJob: Codable, Identifiable, Hashable {
    enum Outcome: String, Codable { case sent, refused, failed }
    var id = UUID()
    var date: Date
    var device: String
    var content: String
    var outcome: Outcome
    var detail: String
    var time: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Refusals

/// Every refusal names itself. The caller is told which of missing / wrong /
/// revoked it was, never a single "unauthorised".
enum RemotePrintRefusal: String, Error {
    case featureOff = "feature_off"
    case missingToken = "missing_token"
    case wrongToken = "wrong_token"
    case revokedToken = "revoked_token"
    case contentNotAllowed = "content_not_allowed"
    case unknownContent = "unknown_content"
    case noPrinter = "no_printer"
    case printFailed = "print_failed"

    var reason: String {
        switch self {
        case .featureOff:
            return "Remote printing is off on this Mac. Turn it on in Settings first."
        case .missingToken:
            return "No device token was sent. Send the token this Mac minted for your device."
        case .wrongToken:
            return "That device token is not one this Mac minted."
        case .revokedToken:
            return "That device token has been revoked. Ask for a new one on this Mac."
        case .contentNotAllowed:
            return "Requests may name one of this app's own items by id. A path, URL, uploaded file or document is refused by name and never printed."
        case .unknownContent:
            return "That item id is not one this Mac holds. Ask for the list of ids first."
        case .noPrinter:
            return "No printer on this Mac accepts that item's size."
        case .printFailed:
            return "The printer did not accept the job."
        }
    }

    var status: Int {
        switch self {
        case .featureOff: return 403
        case .missingToken: return 401
        case .wrongToken, .revokedToken: return 401
        case .contentNotAllowed: return 403
        case .unknownContent, .noPrinter: return 404
        case .printFailed: return 500
        }
    }
}

// MARK: - Remote printing

/// Printing from another device on the tailnet, behind four controls: the
/// switch (off by default), a per-device token, content that this app itself
/// generates and names by id, and an audit line with a kill switch.
///
/// The listener is the app's existing loopback server (`HoldServer`); nothing
/// here opens a port. The tailnet reaches it through `tailscale serve`, which
/// the switch adds and removes.
enum RemotePrint {
    static let enabledKey = "remotePrintEnabled"
    static let servePort: UInt16 = MaintenanceHold.defaultPort
    /// The CLI ships inside the Tailscale app on the App Store build; the other
    /// two are what a Homebrew or standalone install provides. Enabling names
    /// every place it looked when none is there, rather than failing obscurely.
    static let tailscaleCandidates = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
    ]

    static func cliPath() -> String? {
        tailscaleCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Keys a request must never carry: the app prints only what it holds.
    static let forbiddenKeys = ["path", "file", "url", "document", "upload", "command"]
    /// Content ids are the app's own items.
    static let testPageID = "test-page"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var directory: URL {
        ShareFix.supportDirectory.appendingPathComponent("remote", isDirectory: true)
    }
    static var devicesURL: URL { directory.appendingPathComponent("devices.json") }
    static var jobsURL: URL { directory.appendingPathComponent("jobs.json") }
    static let jobLimit = 200

    // MARK: Store

    static func devices() -> [RemoteDevice] {
        guard let data = try? Data(contentsOf: devicesURL),
              let list = try? JSONDecoder().decode([RemoteDevice].self, from: data) else { return [] }
        return list.sorted { $0.createdAt < $1.createdAt }
    }

    private static func save(_ devices: [RemoteDevice]) {
        write(devices, to: devicesURL)
    }

    static func jobs() -> [RemoteJob] {
        guard let data = try? Data(contentsOf: jobsURL),
              let list = try? JSONDecoder().decode([RemoteJob].self, from: data) else { return [] }
        return list
    }

    private static func record(_ job: RemoteJob) {
        var list = jobs()
        list.insert(job, at: 0)
        if list.count > jobLimit { list.removeLast(list.count - jobLimit) }
        write(list, to: jobsURL)
    }

    /// 0600, in a 0700 folder: the tokens are read by anything running as this
    /// person, so they are hashes and nothing else is written after minting.
    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                         attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: Tokens

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The token is returned once, for the person to give to the device. Only
    /// its hash is kept.
    static func mint(name: String) -> (device: RemoteDevice, token: String)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let device = RemoteDevice(id: UUID(), name: String(trimmed.prefix(60)),
                                  tokenHash: hash(token), createdAt: Date())
        save(devices() + [device])
        return (device, token)
    }

    static func revoke(id: UUID) {
        var list = devices()
        guard let index = list.firstIndex(where: { $0.id == id }), !list[index].isRevoked else { return }
        list[index].revokedAt = Date()
        save(list)
    }

    /// The kill switch: every device is refused from the next request on,
    /// because each request reads this store. No restart is involved.
    static func revokeAll() {
        let now = Date()
        save(devices().map { device in
            var copy = device
            if copy.revokedAt == nil { copy.revokedAt = now }
            return copy
        })
    }

    /// Constant-time compare over the digests, so the answer cannot leak how
    /// much of a token matched.
    static func verify(token: String?) -> Result<RemoteDevice, RemotePrintRefusal> {
        guard let token, !token.isEmpty else { return .failure(.missingToken) }
        let offered = Array(hash(token).utf8)
        var match: RemoteDevice?
        for device in devices() {
            let stored = Array(device.tokenHash.utf8)
            var difference = offered.count ^ stored.count
            for index in 0..<max(offered.count, stored.count) {
                difference |= Int(index < offered.count ? offered[index] : 0)
                    ^ Int(index < stored.count ? stored[index] : 0)
            }
            if difference == 0 { match = device }
        }
        guard let match else { return .failure(.wrongToken) }
        if match.isRevoked { return .failure(.revokedToken) }
        var used = match
        used.lastUsedAt = Date()
        var list = devices()
        if let index = list.firstIndex(where: { $0.id == used.id }) {
            list[index] = used
            save(list)
        }
        return .success(used)
    }

    // MARK: Content

    struct Item {
        let id: String
        let name: String
        let widthMM: Double
        let heightMM: Double
    }

    /// The only things a remote caller may name: a test page, and each saved
    /// size the app already holds. No file, path or document exists here.
    static func items() -> [Item] {
        var list = [Item(id: testPageID, name: "Test page", widthMM: 210, heightMM: 297)]
        for size in StickerSizeStore.load() where size.enabled {
            list.append(Item(id: "size:\(size.id.uuidString)", name: size.name,
                             widthMM: size.widthMM, heightMM: size.heightMM))
        }
        return list
    }

    static func item(_ id: String) -> Item? {
        items().first { $0.id == id }
    }

    // MARK: Printing

    /// Sends an item the app composed itself. Returns the queue it used.
    static func print(_ item: Item) -> Result<String, RemotePrintRefusal> {
        guard let data = TestPage.pdf(widthMM: item.widthMM, heightMM: item.heightMM) else {
            return .failure(.unknownContent)
        }
        let printers = CUPS.listPrinters()
        let queue = itemQueue(item, printers: printers)
        guard let queue else { return .failure(.noPrinter) }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PrinterStudio/_trash/remote-pages", isDirectory: true)
        let url = directory.appendingPathComponent("remote-\(UUID().uuidString).pdf")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch { return .failure(.printFailed) }
        let key = PageSizeInstaller.defaultKey(queue: queue.name)
        var arguments = ["-d", queue.name, "-n", "1", "-o", "fit-to-page",
                         "-o", "sides=one-sided", "-o", "job-sheets=none,none"]
        if !key.isEmpty { arguments += ["-o", "PageSize=\(key)"] }
        arguments.append(url.path)
        let result = Shell.run(Tool.lp, arguments)
        return result.ok ? .success(queue.name) : .failure(.printFailed)
    }

    /// The printer that advertises this size; a saved size goes to a queue
    /// whose own paper list contains it, otherwise nothing is printed.
    private static func itemQueue(_ item: Item, printers: [Printer]) -> Printer? {
        guard item.id != testPageID else { return printers.first }
        let key = item.widthMM / 0.1, height = item.heightMM / 0.1
        for printer in printers {
            for choice in PageSizeInstaller.choices(queue: printer.name)
            where Int((choice.widthMM / 0.1).rounded()) == Int(key.rounded())
                && Int((choice.heightMM / 0.1).rounded()) == Int(height.rounded()) {
                return printer
            }
        }
        return nil
    }

    // MARK: The switch and the tailnet

    /// Turns the feature on or off. On: adds the `tailscale serve` mapping to
    /// this loopback port. Off: removes it when it is the only mapping, so a
    /// serve config that is not ours is never wiped.
    static func setEnabled(_ enabled: Bool) -> CommandResult {
        if enabled {
            guard let tailscale = cliPath() else {
                return .failure("Tailscale is not installed here, so this Mac cannot be reached over the tailnet. Looked for it at: \(tailscaleCandidates.joined(separator: ", ")).")
            }
            let result = Shell.run(tailscale, ["serve", "--bg", "\(servePort)"], timeout: 30)
            guard result.ok else {
                return .failure("Tailscale refused to share the port: \(result.combined.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            UserDefaults.standard.set(true, forKey: enabledKey)
            return CommandResult(status: 0, stdout: "Remote printing is on. Only devices with a token can print.", stderr: "")
        }
        UserDefaults.standard.set(false, forKey: enabledKey)
        guard let tailscale = cliPath() else {
            return CommandResult(status: 0, stdout: "Remote printing is off. Tailscale is not installed here.", stderr: "")
        }
        let status = Shell.run(tailscale, ["serve", "status"], timeout: 20)
        let mentionsOurPort = status.stdout.contains("\(servePort)")
        let otherTargets = status.stdout
            .components(separatedBy: .newlines)
            .filter { $0.contains("127.0.0.1:") || $0.contains("localhost:") }
            .filter { !$0.contains("\(servePort)") }
        // Remove the mapping this switch added, and never a serve config that
        // is not ours.
        if mentionsOurPort && otherTargets.isEmpty {
            _ = Shell.run(tailscale, ["serve", "reset"], timeout: 20)
        }
        return CommandResult(status: 0, stdout: "Remote printing is off. No device can print from another machine.", stderr: "")
    }

    // MARK: Routes

    /// Answers `/api/remote/…`. Called from the app's existing loopback
    /// server, so there is one listener and one refusal style.
    static func route(method: String, path: String, request: Data) -> (status: Int, body: Data) {
        let headers = headerValues(request)
        let body = bodyData(request)
        let token = headers["x-device-token"]
        let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]

        guard method == "GET" || method == "POST" else {
            return refuse(.contentNotAllowed, device: "unauthenticated", content: "-")
        }
        guard isEnabled else {
            return refuse(.featureOff, device: deviceName(token), content: "-")
        }
        // A request that carries a path, file, URL or command is refused by
        // name, whether or not it also carries a valid id.
        if let key = payload.keys.first(where: { forbiddenKeys.contains($0.lowercased()) }) {
            return refuse(.contentNotAllowed, device: deviceName(token), content: key)
        }
        let device: RemoteDevice
        switch verify(token: token) {
        case .success(let verified): device = verified
        case .failure(let refusal): return refuse(refusal, device: deviceName(token), content: "-")
        }

        switch (method, path) {
        case ("GET", "/api/remote/content"):
            let items = items().map { ["id": $0.id, "name": $0.name,
                                       "width_mm": $0.widthMM, "height_mm": $0.heightMM] }
            return json(200, ["ok": true, "content": items])
        case ("POST", "/api/remote/print"):
            guard let id = payload["content"] as? String else {
                return refuse(.contentNotAllowed, device: device.name, content: "-")
            }
            guard let item = item(id) else {
                return refuse(.unknownContent, device: device.name, content: id)
            }
            switch print(item) {
            case .success(let queue):
                record(RemoteJob(date: Date(), device: device.name, content: item.name,
                                 outcome: .sent, detail: "Sent to \(queue)."))
                return json(200, ["ok": true, "printed": item.name, "queue": queue])
            case .failure(let refusal):
                return refuse(refusal, device: device.name, content: id)
            }
        case ("GET", "/api/remote/jobs"):
            let list = jobs().prefix(50).map {
                ["time": $0.time, "device": $0.device, "content": $0.content,
                 "outcome": $0.outcome.rawValue, "detail": $0.detail]
            }
            return json(200, ["ok": true, "jobs": Array(list)])
        default:
            return json(404, ["ok": false, "error": "not_found",
                              "reason": "No such route. This server answers /api/remote/content, /api/remote/print and /api/remote/jobs."])
        }
    }

    private static func refuse(_ refusal: RemotePrintRefusal, device: String, content: String) -> (Int, Data) {
        record(RemoteJob(date: Date(), device: device, content: content,
                         outcome: .refused, detail: refusal.rawValue))
        return json(refusal.status, ["ok": false, "error": refusal.rawValue,
                                     "reason": refusal.reason, "guard": "device token and content id"])
    }

    private static func json(_ status: Int, _ object: [String: Any]) -> (Int, Data) {
        (status, (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data("{}".utf8))
    }

    /// A refused caller is labelled by the token prefix it offered, never by a
    /// name it could choose.
    private static func deviceName(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "no token" }
        return "unknown token \(token.prefix(6))…"
    }

    private static func headerValues(_ request: Data) -> [String: String] {
        guard let end = request.range(of: Data("\r\n\r\n".utf8)) else { return [:] }
        let head = String(decoding: request[..<end.lowerBound], as: UTF8.self)
        var values: [String: String] = [:]
        for line in head.split(separator: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }
        return values
    }

    private static func bodyData(_ request: Data) -> Data {
        guard let end = request.range(of: Data("\r\n\r\n".utf8)) else { return Data() }
        return Data(request[end.upperBound...])
    }
}
