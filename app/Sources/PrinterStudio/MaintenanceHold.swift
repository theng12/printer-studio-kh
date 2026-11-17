import Foundation
import Darwin

/// Update hold — the app side of `_orchestra/youtube-stack/update-hold/CONTRACT.md`.
///
/// An update must never interrupt work. The installer asks for a hold before a byte moves: new
/// actions are refused from that instant, the work already running gets a bounded moment to
/// finish, and the reply says whether a restart now would strand anything. The pause is one
/// instant in memory and nothing else — DELETE clears it at once, it expires by itself after
/// `pause_s`, and every start begins open, so an install that aborts can never leave Printer
/// Studio refusing work.
///
/// What counts as work here: the actions this app runs (install, sharing, paper size, test page…),
/// which are the only things a restart can strand. Print jobs are cupsd's, not the app's — they
/// keep printing while Printer Studio KH is replaced, so they are never reported as in flight.
final class MaintenanceHold {
    static let shared = MaintenanceHold()

    /// The port the published feed names for this app's hold endpoint.
    static let defaultPort: UInt16 = 8642

    // Contract bounds: settle within 20 s, never past 30; the pause defaults to two minutes.
    static let defaultTimeoutS = 20
    static let maxTimeoutS = 30
    static let defaultPauseS = 120
    static let minPauseS = 1
    static let maxPauseS = 900

    /// Plain words for a person whose action was refused during a hold.
    static let refusal = "Printer Studio KH is pausing for an update, so nothing new starts yet. Try again in a moment."

    private let lock = NSLock()
    /// In memory only, never written down: a restart always starts open.
    private var pausedUntil: Date?
    private var running: [Int: String] = [:]
    private var nextID = 0

    // MARK: The pause

    private func pausedLocked(_ now: Date) -> Bool {
        guard let until = pausedUntil else { return false }
        if now < until { return true }
        pausedUntil = nil
        return false
    }

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pausedLocked(Date())
    }

    func pause(seconds: Int) {
        lock.lock()
        defer { lock.unlock() }
        pausedUntil = Date().addingTimeInterval(TimeInterval(seconds))
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        pausedUntil = nil
    }

    // MARK: Work claimed under it

    /// Registers an action and refuses it while a hold stands. Nil means nothing started; the
    /// caller settles the same id when it ends.
    func claim(_ label: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !pausedLocked(Date()) else { return nil }
        nextID += 1
        running[nextID] = label
        return nextID
    }

    func settle(_ id: Int) {
        lock.lock()
        defer { lock.unlock() }
        running[id] = nil
    }

    /// The action path's one gate: the claim, or the words to show when refused. `perform` calls
    /// this, so the refusal text the person sees is the one the tests check.
    func claimOrRefuse(_ label: String) -> (claim: Int?, refusal: String?) {
        if let id = claim(label) { return (id, nil) }
        return (nil, Self.refusal)
    }

    /// Registers work that must never be refused: taking the app off this Mac is the person's own
    /// choice, not work an update could strand. It is still counted, so `in_flight` stays true.
    func register(_ label: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        nextID += 1
        running[nextID] = label
        return nextID
    }

    var inFlight: Int {
        lock.lock()
        defer { lock.unlock() }
        return running.count
    }

    /// The work still running, oldest first, each with the id a later look can follow.
    var runningLabels: [String] {
        lock.lock()
        defer { lock.unlock() }
        return running.keys.sorted().map { "\(running[$0] ?? "action")#\($0)" }
    }

    /// Waits up to the ceiling for running work to end — never for the work to finish.
    func settleWindow(seconds: Int) -> [String] {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while true {
            let left = runningLabels
            let remaining = deadline.timeIntervalSinceNow
            if left.isEmpty || remaining <= 0 { return left }
            Thread.sleep(forTimeInterval: min(0.1, remaining))
        }
    }

    // MARK: Shapes

    static func bounded(_ raw: String?, _ fallback: Int, min lo: Int, max hi: Int) -> Int {
        guard let raw, let value = Int(raw.trimmingCharacters(in: .whitespaces)) else { return fallback }
        return Swift.min(Swift.max(value, lo), hi)
    }

    /// The reply every app in the contract returns, key for key.
    struct Reply {
        var safe: Bool
        var unsettled: [String]
        var dispatchPausedS: Int
        var inFlight: Int

        var json: Data {
            let object: [String: Any] = [
                "safe": safe,
                "unsettled": unsettled,
                "dispatch_paused_s": dispatchPausedS,
                "in_flight": inFlight,
            ]
            return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                ?? Data("{}".utf8)
        }
    }

    /// What the person is told while the app is held, and when it lets go. Plain words.
    static func heldNotice(inFlight: Int, seconds: Int) -> String {
        inFlight == 0
            ? "Paused for an update. Nothing new starts for up to \(seconds) seconds, then it carries on by itself."
            : "Paused for an update; \(inFlight) action\(inFlight == 1 ? "" : "s") still finishing."
    }

    static let resumedNotice = "Update hold released — Printer Studio KH is working again."
}

/// The loopback HTTP the installer talks to. Only this Mac can pause the app: the listener binds
/// 127.0.0.1 and nothing else, and the hold route takes the credential the updater sent, so a
/// local process cannot pause or release the hold without the token file.
final class HoldServer {
    private let hold: MaintenanceHold
    private let port: UInt16
    /// The token file the updater writes before it calls; the hold route answers nothing without it.
    private let tokenPath: String
    private let onHeld: (Int, Int) -> Void
    private let onResumed: () -> Void
    private var listenFD: Int32 = -1

    init(hold: MaintenanceHold = .shared,
         port: UInt16 = MaintenanceHold.defaultPort,
         tokenPath: String? = nil,
         onHeld: @escaping (Int, Int) -> Void,
         onResumed: @escaping () -> Void) {
        self.hold = hold
        self.port = port
        self.tokenPath = tokenPath
            ?? ProcessInfo.processInfo.environment["PRINTER_STUDIO_HOLD_TOKEN_FILE"]
            ?? NSHomeDirectory() + "/Library/KHUpdater/state/hold-token"
        self.onHeld = onHeld
        self.onResumed = onResumed
    }

    deinit {
        if listenFD >= 0 { close(listenFD) }
    }

    /// Binds loopback and starts answering. Returns the port actually used (the system picks one
    /// when `port` is 0), or nil when the address could not be taken.
    @discardableResult
    func start() -> UInt16? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            return nil
        }

        var actual = address
        var actualSize = size
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &actualSize) }
        }
        listenFD = fd
        let listening = UInt16(bigEndian: actual.sin_port)
        Thread.detachNewThread { [weak self] in self?.acceptLoop(fd) }
        return listening
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            Thread.detachNewThread { [weak self] in self?.handle(client) }
        }
    }

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        guard let request = Self.read(fd) else { return }
        let (method, target) = Self.requestLine(request)
        let (path, query) = Self.split(target)

        // The hold route takes the updater's credential; every other route stays open as before.
        if path == "/api/maintenance/hold" && (method == "POST" || method == "DELETE") {
            let configured = configuredToken()
            let offered = Self.offeredCredential(request)
            guard let configured, let offered, Self.sameToken(offered, configured) else {
                Self.send(fd, status: 401, body: Data("{\"error\":\"unauthorized\"}".utf8))
                return
            }
        }

        switch (method, path) {
        case ("POST", "/api/maintenance/hold"):
            let timeout = MaintenanceHold.bounded(query["timeout_s"], MaintenanceHold.defaultTimeoutS,
                                                  min: 0, max: MaintenanceHold.maxTimeoutS)
            let pause = MaintenanceHold.bounded(query["pause_s"], MaintenanceHold.defaultPauseS,
                                                min: MaintenanceHold.minPauseS, max: MaintenanceHold.maxPauseS)
            // The claim path closes here, before any waiting.
            hold.pause(seconds: pause)
            onHeld(hold.inFlight, pause)
            // Bounded settle: never waits for the work to finish, only up to the deadline.
            let unsettled = hold.settleWindow(seconds: timeout)
            // Counted when the answer is made, not when the hold was taken: work that finished
            // inside the window must not still be reported as running.
            Self.send(fd, status: 200, body: MaintenanceHold.Reply(
                safe: unsettled.isEmpty, unsettled: unsettled,
                dispatchPausedS: pause, inFlight: hold.inFlight).json)
        case ("DELETE", "/api/maintenance/hold"):
            hold.resume()
            onResumed()
            Self.send(fd, status: 200, body: MaintenanceHold.Reply(
                safe: true, unsettled: [],
                dispatchPausedS: 0, inFlight: hold.inFlight).json)
        default:
            Self.send(fd, status: 404, body: Data("{\"error\":\"not found\"}".utf8))
        }
    }

    /// The token the updater writes (0600, plain text) before it calls. Read once per request. A
    /// missing or empty file means an old or absent updater that will never send the credential,
    /// so refusing the hold is the safe direction — the updater fails closed on any non-200.
    private func configuredToken() -> String? {
        guard let text = try? String(contentsOfFile: tokenPath, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: HTTP

    /// `X-Hub-Token: t` or `Authorization: Bearer t`, whichever the updater sent.
    private static func offeredCredential(_ request: Data) -> String? {
        if let token = header(request, "x-hub-token") { return token }
        if let auth = header(request, "authorization"), auth.hasPrefix("Bearer ") {
            return auth.dropFirst("Bearer ".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func header(_ request: Data, _ name: String) -> String? {
        guard let end = request.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: request[..<end.lowerBound], as: UTF8.self)
        for line in head.split(separator: "\r\n").dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == name {
                return kv[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Constant-time byte compare: no early exit, so the answer cannot leak how much matched.
    private static func sameToken(_ offered: String, _ configured: String) -> Bool {
        let a = Array(offered.utf8), b = Array(configured.utf8)
        var diff = a.count ^ b.count
        for i in 0..<max(a.count, b.count) {
            diff |= Int(i < a.count ? a[i] : 0) ^ Int(i < b.count ? b[i] : 0)
        }
        return diff == 0
    }

    /// Headers (at most 64 KiB), then exactly Content-Length body bytes, within a deadline.
    private static func read(_ fd: Int32, deadline: TimeInterval = 15) -> Data? {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        let separator = Data("\r\n\r\n".utf8)
        let until = Date().addingTimeInterval(deadline)
        while true {
            if let end = data.range(of: separator) {
                let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).lowercased()
                let length = head.split(separator: "\r\n")
                    .first { $0.hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                if length < 0 || length > (1 << 20) { return nil }
                if data.count - end.upperBound >= length {
                    return Data(data.prefix(end.upperBound + length))
                }
            } else if data.count > 65536 {
                return nil
            }
            let remaining = until.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(remaining, 15) * 1000))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return nil }
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count <= 0 { return nil }
            data.append(contentsOf: chunk[0..<count])
        }
    }

    /// "POST /api/maintenance/hold?timeout_s=20 HTTP/1.1" → method and target.
    private static func requestLine(_ data: Data) -> (String, String) {
        guard let end = data.range(of: Data("\r\n".utf8)) else { return ("", "") }
        let parts = String(decoding: data[..<end.lowerBound], as: UTF8.self).split(separator: " ")
        guard parts.count >= 2 else { return ("", "") }
        return (String(parts[0]).uppercased(), String(parts[1]))
    }

    private static func split(_ target: String) -> (String, [String: String]) {
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var query: [String: String] = [:]
        if parts.count == 2 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard let name = kv.first else { continue }
                query[String(name)] = kv.count == 2 ? String(kv[1]) : ""
            }
        }
        return (String(parts[0]), query)
    }

    private static func send(_ fd: Int32, status: Int, body: Data) {
        var out = "HTTP/1.1 \(status) \(status == 200 ? "OK" : status == 401 ? "Unauthorized" : "Not Found")\r\n"
        out += "Content-Type: application/json\r\n"
        out += "Content-Length: \(body.count)\r\n"
        out += "Connection: close\r\n\r\n"
        var packet = Data(out.utf8)
        packet.append(body)
        packet.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < packet.count {
                let count = Darwin.write(fd, base + sent, packet.count - sent)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { return }
                sent += count
            }
        }
    }
}
