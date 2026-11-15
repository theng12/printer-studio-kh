import Foundation
import Darwin

/// Checks the app-side update hold against `_orchestra/youtube-stack/update-hold/CONTRACT.md`:
/// the pause, the real in-flight count, the bounded settle, the release, an abandoned hold
/// expiring by itself, a fresh start opening, and the loopback route itself over real HTTP.
@main
struct TestMaintenanceHold {
    static var failures = 0

    static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS: \(name)")
        } else {
            failures += 1
            print("FAIL: \(name)")
        }
    }

    static func main() {
        bounded()
        theHoldStartsOpen()
        aHoldRefusesNewWorkInPlainWords()
        inFlightIsReal()
        theSettleIsBounded()
        deleteResumesAtOnce()
        anAbandonedHoldExpiresByItself()
        aFreshStartOpens()
        theRouteOverRealHTTP()
        theReplyCountsWorkWhenItAnswers()

        if failures > 0 {
            print("FAILED: \(failures) check(s)")
            exit(1)
        }
        print("PASS: update hold")
    }

    // MARK: The contract's numbers

    static func bounded() {
        check("timeout defaults to 20 s", MaintenanceHold.bounded(nil, MaintenanceHold.defaultTimeoutS, min: 0, max: MaintenanceHold.maxTimeoutS) == 20)
        check("timeout never exceeds 30 s", MaintenanceHold.bounded("999", 20, min: 0, max: 30) == 30)
        check("a negative wait is no wait", MaintenanceHold.bounded("-4", 20, min: 0, max: 30) == 0)
        check("garbage is the default", MaintenanceHold.bounded("soon", 20, min: 0, max: 30) == 20)
        check("the pause defaults to 120 s", MaintenanceHold.bounded(nil, MaintenanceHold.defaultPauseS, min: MaintenanceHold.minPauseS, max: MaintenanceHold.maxPauseS) == 120)
        check("the pause always has a moment", MaintenanceHold.bounded("0", 120, min: 1, max: 900) == 1)
        check("the pause is bounded too", MaintenanceHold.bounded("100000", 120, min: 1, max: 900) == 900)
        check("the published port is 8642", MaintenanceHold.defaultPort == 8642)
    }

    // MARK: The pause and the work under it

    static func theHoldStartsOpen() {
        let hold = MaintenanceHold()
        check("a fresh hold is open", !hold.isPaused)
        check("nothing is in flight on a fresh hold", hold.inFlight == 0)
    }

    static func aHoldRefusesNewWorkInPlainWords() {
        let hold = MaintenanceHold()
        hold.pause(seconds: 120)
        check("the pause stands", hold.isPaused)
        check("a held app refuses to start work", hold.claim("Installing the printer driver…") == nil)
        check("nothing started, so nothing is in flight", hold.inFlight == 0)
        check("the refusal says why in plain words",
              MaintenanceHold.refusal.contains("pausing for an update")
              && MaintenanceHold.refusal.contains("Try again in a moment")
              && !MaintenanceHold.refusal.contains("hold")
              && !MaintenanceHold.refusal.contains("API"))

        // The gate the action path itself calls: same answer, same words.
        let gate = hold.claimOrRefuse("Installing the printer driver…")
        check("the action path's gate refuses while held", gate.claim == nil && gate.refusal == MaintenanceHold.refusal)
        hold.resume()
        let open = hold.claimOrRefuse("Installing the printer driver…")
        check("the action path's gate claims when open", open.claim != nil && open.refusal == nil)
        if let id = open.claim { hold.settle(id) }

        // Removing the app is never refused, but is counted while a hold stands.
        hold.pause(seconds: 120)
        let removal = hold.register("Removing Printer Studio KH from this Mac…")
        check("removal is allowed during a hold and counted", hold.inFlight == 1)
        hold.settle(removal)
        check("removal is done", hold.inFlight == 0)
    }

    static func inFlightIsReal() {
        let hold = MaintenanceHold()
        let first = hold.claim("Installing the printer driver…")
        check("a claim is registered", first != nil && hold.inFlight == 1)
        let second = hold.claim("Setting paper size…")
        check("two actions are two in flight", second != nil && hold.inFlight == 2)
        if let first { hold.settle(first) }
        check("one finished, one still running", hold.inFlight == 1)
        if let second { hold.settle(second) }
        check("both finished", hold.inFlight == 0)
        // Settling twice must never subtract someone else's work.
        if let first { hold.settle(first) }
        check("settling twice changes nothing", hold.inFlight == 0)
    }

    static func theSettleIsBounded() {
        let hold = MaintenanceHold()
        guard let claim = hold.claim("Opening shared queues to the LAN…") else {
            check("the work started", false)
            return
        }
        hold.pause(seconds: 120)
        let start = Date()
        let unsettled = hold.settleWindow(seconds: 0)
        let elapsed = Date().timeIntervalSince(start)
        check("past the deadline the running work is named", unsettled.count == 1 && unsettled[0].hasPrefix("Opening shared queues to the LAN…"))
        check("the settle never waits for the work to finish", elapsed < 1)
        hold.settle(claim)
        check("nothing running, nothing unsettled", hold.settleWindow(seconds: 1).isEmpty)

        // Work that ends inside the window is waited for, and only that long.
        let hold2 = MaintenanceHold()
        let claim2 = hold2.claim("Sending one test page…")
        let started = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if let claim2 { hold2.settle(claim2) }
        }
        let left = hold2.settleWindow(seconds: 5)
        let waited = Date().timeIntervalSince(started)
        check("work that finishes inside the window settles", left.isEmpty)
        check("the settle ends when the work does", waited < 2)
    }

    static func deleteResumesAtOnce() {
        let hold = MaintenanceHold()
        hold.pause(seconds: 900)
        check("held", hold.claim("Refreshing…") == nil)
        hold.resume()
        check("DELETE resumes at once", !hold.isPaused)
        check("work starts again", hold.claim("Refreshing…") != nil)
    }

    static func anAbandonedHoldExpiresByItself() {
        let hold = MaintenanceHold()
        hold.pause(seconds: 1)
        check("the pause stands at first", hold.isPaused && hold.claim("Refreshing…") == nil)
        Thread.sleep(forTimeInterval: 1.1)
        check("no DELETE: the pause expires by itself", !hold.isPaused)
        check("work starts again after the pause", hold.claim("Refreshing…") != nil)
    }

    static func aFreshStartOpens() {
        let old = MaintenanceHold()
        old.pause(seconds: 900)
        _ = old.claim("Installing the printer driver…")
        // A restart is a new instance: it holds nothing and was written nowhere.
        let restarted = MaintenanceHold()
        check("a restart dispatches with no manual step", !restarted.isPaused && restarted.inFlight == 0)
        check("the old instance still holds its own pause", old.isPaused)
    }

    // MARK: The route, over real HTTP

    static func theRouteOverRealHTTP() {
        let hold = MaintenanceHold()
        let server = HoldServer(hold: hold, port: 0,
                                onHeld: { _, _ in }, onResumed: { })
        guard let port = server.start() else {
            check("the hold listener started", false)
            return
        }
        check("the listener started on a loopback port", port > 0)
        let base = "http://127.0.0.1:\(port)/api/maintenance/hold"

        let (status, reply) = send("POST", base + "?timeout_s=0&pause_s=120")
        check("POST answers 200", status == 200)
        check("the reply carries exactly the contract's keys",
              Set(reply.keys) == ["safe", "unsettled", "dispatch_paused_s", "in_flight"])
        check("an idle app is safe to replace", reply["safe"] as? Bool == true)
        check("the pause the reply names is the pause taken", reply["dispatch_paused_s"] as? Int == 120)
        check("in_flight is real: nothing running", reply["in_flight"] as? Int == 0)
        check("the route paused the app", hold.isPaused && hold.claim("Refreshing…") == nil)

        let (resumedStatus, resumed) = send("DELETE", base)
        check("DELETE answers 200", resumedStatus == 200)
        check("DELETE resumes at once", !hold.isPaused && resumed["dispatch_paused_s"] as? Int == 0)
        check("DELETE reports what is still running", resumed["in_flight"] as? Int == 0)

        // Live work: the reply must count it and name what a restart would strand.
        guard let claim = hold.claim("Installing the printer driver…") else {
            check("work could be claimed once resumed", false)
            return
        }
        let (busyStatus, busy) = send("POST", "\(base)?timeout_s=0&pause_s=120")
        check("a held app with work running still answers", busyStatus == 200)
        check("in_flight matches reality", busy["in_flight"] as? Int == 1)
        check("work past the deadline is not safe to strand", busy["safe"] as? Bool == false)
        check("the unsettled work is named", (busy["unsettled"] as? [String])?.count == 1)
        hold.settle(claim)

        let (unknown, _) = send("GET", base)
        check("another request is not the hold", unknown == 404)

        // Only this Mac may pause the app: the listener binds 127.0.0.1, nothing else.
        if let outside = nonLoopbackIPv4() {
            let reachable = connect(host: outside, port: port)
            check("the hold is not reachable from \(outside)", !reachable)
        } else {
            print("SKIP: no non-loopback address on this Mac to try")
        }
    }

    /// The number the installer shows must be true when the reply is made, not when the hold was
    /// taken: work that finished inside the window is not still running.
    static func theReplyCountsWorkWhenItAnswers() {
        let hold = MaintenanceHold()
        let server = HoldServer(hold: hold, port: 0, onHeld: { _, _ in }, onResumed: { })
        guard let port = server.start() else {
            check("the listener started for the timing check", false)
            return
        }
        let claim = hold.claim("Sending one test page…")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if let claim { hold.settle(claim) }
        }
        let (status, reply) = send("POST", "http://127.0.0.1:\(port)/api/maintenance/hold?timeout_s=3&pause_s=120",
                                   timeout: 10)
        check("a hold that settles inside its window answers 200", status == 200)
        check("finished work is not still counted as running", reply["in_flight"] as? Int == 0)
        check("the answer agrees with itself",
              reply["safe"] as? Bool == true && (reply["unsettled"] as? [String])?.isEmpty == true)
    }

    // MARK: Helpers
    static func send(_ method: String, _ url: String, timeout: TimeInterval = 5) -> (Int, [String: Any]) {
        guard let target = URL(string: url) else { return (-1, [:]) }
        var request = URLRequest(url: target)
        request.httpMethod = method
        if method == "POST" { request.httpBody = Data() }
        request.timeoutInterval = timeout
        var status = -1
        var body = Data()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? -1
            body = data ?? Data()
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 2)
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        return (status, object)
    }

    /// True when a plain TCP connect to the address succeeds; the hold must not answer off-Mac.
    static func connect(host: String, port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr(host)
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) }
        } == 0
    }

    static func nonLoopbackIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let size = socklen_t(address.pointee.sa_len)
            guard getnameinfo(address, size, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            if text.hasPrefix("169.254.") { continue }
            return text
        }
        return nil
    }
}
