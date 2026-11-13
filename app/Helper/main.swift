import Foundation
import dnssd

// Every background job Printer Studio KH installs runs through this one helper, so
// Activity Monitor and launchd show the app's own name instead of bash scripts.
// Transient work still calls the same system tools the scripts called.

let usage = "usage: Printer Studio KH Helper [all|bridge|sharefix|usb|list|selftest]"

let environment = ProcessInfo.processInfo.environment

func toolPath(_ name: String, fallback: String) -> String {
    guard let directory = environment["PRINTER_STUDIO_TOOL_DIR"], !directory.isEmpty else {
        return fallback + "/" + name
    }
    return directory + "/" + name
}

let lpstat = toolPath("lpstat", fallback: "/usr/bin")
let lpoptions = toolPath("lpoptions", fallback: "/usr/bin")
let cupsctl = toolPath("cupsctl", fallback: "/usr/sbin")
let ipptool = toolPath("ipptool", fallback: "/usr/bin")
let dnsSD = toolPath("dns-sd", fallback: "/usr/bin")
let hostname = toolPath("hostname", fallback: "/bin")
let lpadmin = toolPath("lpadmin", fallback: "/usr/sbin")
let pgrep = toolPath("pgrep", fallback: "/usr/bin")
let ps = toolPath("ps", fallback: "/bin")
let kill = toolPath("kill", fallback: "/bin")

// MARK: - Process helpers

struct Output {
    let status: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { status == 0 }
}

func run(_ path: String, _ arguments: [String] = []) -> Output {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do {
        try process.run()
    } catch {
        return Output(status: -1, stdout: "", stderr: "\(error)")
    }
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Output(status: process.terminationStatus,
                  stdout: String(decoding: outData, as: UTF8.self),
                  stderr: String(decoding: errData, as: UTF8.self))
}

func outputLines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data((message.hasSuffix("\n") ? message : message + "\n").utf8))
}

// MARK: - Shared printer plan

struct QueueFlags {
    let color: String
    let duplex: String
}

let uuidPattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"

func sharingEnabled() -> Bool {
    outputLines(run(cupsctl).stdout).contains("_share_printers=1")
}

func printerModel(_ queue: String) -> String {
    var label = ""
    for line in outputLines(run(lpstat, ["-l", "-p", queue]).stdout) {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("Description:") else { continue }
        label = String(trimmed.dropFirst("Description:".count)
            .drop(while: { $0 == " " || $0 == "\t" }))
        break
    }
    if label.isEmpty {
        for line in outputLines(run(lpoptions, ["-p", queue]).stdout) {
            guard let start = line.range(of: "printer-make-and-model='") else { continue }
            let rest = line[start.upperBound...]
            guard let end = rest.firstIndex(of: "'") else { continue }
            label = String(rest[..<end])
            break
        }
    }
    return label.isEmpty ? queue : label
}

func queueFlags(_ queue: String) -> QueueFlags {
    var color = ""
    var duplex = ""
    for line in outputLines(run(lpoptions, ["-p", queue, "-l"]).stdout) {
        guard let separator = line.range(of: ": ") else { continue }
        var key = String(line[..<separator.lowerBound])
        if let slash = key.firstIndex(of: "/") { key = String(key[..<slash]) }
        let value = String(line[separator.upperBound...])
        if key == "ColorModel" || key == "BRMonoColor" { color = value }
        if key == "Duplex" { duplex = value }
    }
    return QueueFlags(
        color: color.range(of: "RGB|CMYK", options: .regularExpression) != nil ? "T" : "F",
        duplex: duplex.range(of: "DuplexTumble|DuplexNoTumble", options: .regularExpression) != nil ? "T" : "F")
}

func attributeUUID(_ attributes: String) -> String? {
    for line in outputLines(attributes) {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 4, fields[0] == "printer-uuid", fields[2] == "=" else { continue }
        var uuid = String(fields[3])
        if uuid.hasPrefix("urn:uuid:") { uuid = String(uuid.dropFirst("urn:uuid:".count)) }
        guard uuid.range(of: uuidPattern, options: .regularExpression) != nil else { return nil }
        return uuid.lowercased()
    }
    return nil
}

func queueUUID(_ queue: String) -> String? {
    let attributes = run(ipptool, ["-tv", "ipp://localhost/printers/\(queue)",
                                   "get-printer-attributes.test"])
    if attributes.ok, let uuid = attributeUUID(attributes.stdout) { return uuid }
    note("AirPrint: no valid CUPS printer-uuid for \(queue); keeping its legacy advertisement.")
    return nil
}

func shortHostName() -> String {
    run(hostname, ["-s"]).stdout.trimmingCharacters(in: .newlines)
}

func advertisementArgs(_ queue: String) -> [String] {
    let model = printerModel(queue)
    let flags = queueFlags(queue)
    var arguments = [
        "-R", "\(model) (AirPrint)", "_ipp._tcp,_universal", "local", "631",
        "txtvers=1", "qtotal=1", "rp=printers/\(queue)", "ty=\(model)",
        "product=(\(model))", "note=\(queue) on \(shortHostName())",
        "pdl=application/pdf,image/jpeg,image/urf", "URF=none",
        "Color=\(flags.color)", "Duplex=\(flags.duplex)",
    ]
    if let uuid = queueUUID(queue) { arguments.append("UUID=\(uuid)") }
    return arguments
}

// MARK: - Native AirPrint detection

func queryDnssd(_ arguments: [String]) -> Output {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: dnsSD)
    process.arguments = ["-lo", "-m"] + arguments
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do {
        try process.run()
    } catch {
        return Output(status: -1, stdout: "", stderr: "")
    }
    // Bound a cache miss; never wait indefinitely for a native DNS-SD service.
    let seconds = Double(environment["PRINTER_STUDIO_DNSSD_SECONDS"] ?? "") ?? 2
    if finished.wait(timeout: .now() + seconds) == .timedOut {
        if process.isRunning { process.terminate() }
        _ = finished.wait(timeout: .now() + 1)
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    _ = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Output(status: process.terminationStatus,
                  stdout: String(decoding: data, as: UTF8.self), stderr: "")
}

func confirmsNative(_ text: String, queue: String, uuid: String) -> Bool {
    var endpoint = false
    var route = false
    var identity = false
    var urf = false
    var pdl = false
    for line in outputLines(text) {
        if line.contains("can be reached at "), line.contains(":631 (interface ") {
            endpoint = true
        }
        for token in line.split(whereSeparator: \.isWhitespace) {
            if token == "rp=printers/\(queue)" { route = true }
            if token.lowercased() == "uuid=\(uuid)" { identity = true }
            if token.hasPrefix("URF="), token.count > 4 { urf = true }
            if token.hasPrefix("pdl=") {
                let formats = token.dropFirst(4).split(separator: ",")
                if formats.contains(where: { $0 == "application/pdf" || $0 == "image/urf" }) {
                    pdl = true
                }
            }
        }
    }
    return endpoint && route && identity && urf && pdl
}

func browseConfirms(_ text: String, name: String) -> Bool {
    for line in outputLines(text) {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, fields[1] == "Add" else { continue }
        if let range = line.range(of: "^.*_ipp\\._tcp\\.\\s+", options: .regularExpression),
           String(line[range.upperBound...]) == name {
            return true
        }
    }
    return false
}

func nativeAirprint(_ queue: String) -> Bool {
    let attributes = run(ipptool, ["-tv", "ipp://localhost/printers/\(queue)",
                                   "get-printer-attributes.test"])
    guard attributes.ok, let uuid = attributeUUID(attributes.stdout) else { return false }

    var name = ""
    for line in outputLines(attributes.stdout) {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("printer-dns-sd-name ") else { continue }
        guard let separator = line.range(of: " = ", options: .backwards) else { continue }
        name = String(line[separator.upperBound...])
        break
    }
    guard !name.isEmpty else { return false }

    let resolved = queryDnssd(["-L", name, "_ipp._tcp", "local."])
    guard resolved.ok, confirmsNative(resolved.stdout, queue: queue, uuid: uuid) else { return false }
    let browsed = queryDnssd(["-B", "_ipp._tcp,_universal", "local."])
    guard browsed.ok, browseConfirms(browsed.stdout, name: name) else { return false }
    return true
}

func sharedPrinters() -> [String] {
    var shared: [String] = []
    for line in outputLines(run(lpstat, ["-p"]).stdout) {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, fields[0] == "printer" else { continue }
        let queue = String(fields[1])
        guard run(lpoptions, ["-p", queue]).stdout.contains("printer-is-shared=true") else {
            continue
        }
        if nativeAirprint(queue) {
            note("AirPrint: \(queue) already has a matching local AirPrint service; no bridge twin.")
        } else {
            shared.append(queue)
        }
    }
    return shared.sorted()
}

// MARK: - Bonjour registration

var registrations: [DNSServiceRef] = []

let registrationCallback: DNSServiceRegisterReply = { _, _, error, _, _, _, _ in
    if error != kDNSServiceErr_NoError {
        note("AirPrint: Bonjour registration error \(error).")
    }
}

/// True when every name we advertise is still visible on the network. A browse
/// that itself fails returns true, so a flaky query never causes churn.
func advertisementsAlive(_ names: [String]) -> Bool {
    let browsed = queryDnssd(["-B", "_ipp._tcp,_universal", "local."])
    guard browsed.ok else { return true }
    return names.allSatisfy { browseConfirms(browsed.stdout, name: $0) }
}

func withdrawAll() {
    for reference in registrations { DNSServiceRefDeallocate(reference) }
    registrations.removeAll()
}

func txtRecord(_ entries: [String]) -> Data {
    var data = Data()
    for entry in entries {
        let bytes = Array(entry.utf8)
        let count = min(bytes.count, 255)
        data.append(UInt8(count))
        data.append(contentsOf: bytes.prefix(count))
    }
    return data
}

func register(_ arguments: [String]) -> Bool {
    guard arguments.count >= 5, let port = UInt16(arguments[4]) else { return false }
    let name = arguments[1]
    let regtype = arguments[2]
    let domain = arguments[3]
    let txt = txtRecord(Array(arguments.dropFirst(5)))
    var reference: DNSServiceRef?
    let error = txt.withUnsafeBytes { buffer -> DNSServiceErrorType in
        DNSServiceRegister(&reference, kDNSServiceFlagsNoAutoRename, 0,
                           name, regtype, domain, nil, port.bigEndian,
                           UInt16(txt.count), buffer.baseAddress,
                           registrationCallback, nil)
    }
    guard error == kDNSServiceErr_NoError, let reference else {
        note("AirPrint: could not advertise \(name) (Bonjour error \(error)).")
        return false
    }
    registrations.append(reference)
    return true
}

func handleTermination(_ signalNumber: Int32) {
    withdrawAll()
    exit(0)
}

func processResults(timeoutMilliseconds: Int32) {
    guard !registrations.isEmpty else {
        Thread.sleep(forTimeInterval: Double(timeoutMilliseconds) / 1000)
        return
    }
    var descriptors = registrations.map {
        pollfd(fd: DNSServiceRefSockFD($0), events: Int16(POLLIN), revents: 0)
    }
    let ready = descriptors.withUnsafeMutableBufferPointer {
        poll($0.baseAddress, nfds_t($0.count), timeoutMilliseconds)
    }
    guard ready > 0 else { return }
    for (index, descriptor) in descriptors.enumerated() where descriptor.revents != 0 {
        if DNSServiceProcessResult(registrations[index]) != kDNSServiceErr_NoError { exit(1) }
    }
}

// MARK: - Orphan guard

/// The labels the app's plists use, by mode. `all` is the one installed job:
/// the AirPrint bridge and the share-fix pass run together in this process.
let jobLabels = ["all": "com.theng12.printerstudio.airprint",
                 "bridge": "com.theng12.printerstudio.airprint",
                 "sharefix": "com.theng12.printerstudio.sharefix"]

/// The helper ships inside the app bundle. If that bundle is dragged to the
/// Trash, its launchd job would point at a missing program for ever; the helper
/// notices, retires its own plist and unloads the job instead of leaving an
/// orphan. `PRINTER_STUDIO_JOB_LABEL` lets a test use a throwaway label.
@discardableResult
func clearOwnJobIfBundleIsGone(_ mode: String) -> Bool {
    guard let label = environment["PRINTER_STUDIO_JOB_LABEL"] ?? jobLabels[mode] else { return false }
    var url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    var outermost: URL?
    while url.pathComponents.count > 1 {
        url.deleteLastPathComponent()
        if url.pathExtension == "app" { outermost = url }
    }
    guard let app = outermost, !FileManager.default.fileExists(atPath: app.path) else { return false }

    let home = URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory(), isDirectory: true)
    let plist = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
    let trash = home.appendingPathComponent("Desktop/_trash/\(day) printer-studio-kh-orphaned-jobs", isDirectory: true)
    if FileManager.default.fileExists(atPath: plist.path) {
        try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: plist, to: trash.appendingPathComponent(plist.lastPathComponent))
    }
    _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
    note("The app is no longer on this Mac, so this helper removed its own background job (\(label)).")
    return true
}

// MARK: - Modes

/// `shareFixEvery` > 0 makes the same loop run the share-fix pass on that
/// interval. The `all` mode uses it, so Login Items shows one helper job.
func runBridge(mode: String = "bridge", shareFixEvery: Int = 0) {
    signal(SIGTERM, handleTermination)
    signal(SIGINT, handleTermination)
    let rescan = max(1, Int(environment["PRINTER_STUDIO_RESCAN_SECONDS"] ?? "") ?? 60)
    var current = ""
    var advertisedNames: [String] = []
    var cyclesSinceChange = 0
    var nextShareFix = Date().addingTimeInterval(TimeInterval(shareFixEvery))
    while true {
        // The app can be dragged to the Trash while this job is running.
        if clearOwnJobIfBundleIsGone(mode) { exit(0) }
        if shareFixEvery > 0, Date() >= nextShareFix {
            runShareFix()
            nextShareFix = Date().addingTimeInterval(TimeInterval(shareFixEvery))
        }
        var plans: [(queue: String, arguments: [String])] = []
        if sharingEnabled() {
            for queue in sharedPrinters() {
                plans.append((queue, advertisementArgs(queue)))
            }
        }
        let found = plans.flatMap { $0.arguments }.joined(separator: "\n")
        if found != current {
            withdrawAll()
            current = found
            advertisedNames = plans.map { $0.arguments[1] }
            cyclesSinceChange = 0
            for plan in plans { _ = register(plan.arguments) }
        } else {
            cyclesSinceChange += 1
            // A registration can be lost without the process noticing — a name
            // conflict while updating, or mDNSResponder restarting. Re-announce
            // rather than stay silent until someone restarts the job.
            if !advertisedNames.isEmpty, cyclesSinceChange > 1, !advertisementsAlive(advertisedNames) {
                note("An AirPrint advertisement went missing; announcing it again.")
                withdrawAll()
                current = ""
            }
        }
        // Keep Bonjour callbacks serviced while waiting for the next scan.
        for _ in 0..<rescan { processResults(timeoutMilliseconds: 1000) }
    }
}

func runList() {
    if sharingEnabled() {
        for queue in sharedPrinters() {
            print("Shared queue: \(queue)")
            for argument in advertisementArgs(queue) { print(argument) }
        }
    } else {
        print("Printer Sharing is off, so nothing would be advertised.")
    }
}

func appendLog(_ text: String, to path: String) {
    let url = URL(fileURLWithPath: path)
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
    } catch {
        return
    }
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(Data((text + "\n").utf8))
        try? handle.close()
    } else {
        try? Data((text + "\n").utf8).write(to: url)
    }
}

func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: Date())
}

func runShareFix() {
    let log = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/PrinterStudio/share-fix.log").path
    var changed = false
    for line in outputLines(run(lpstat, ["-p"]).stdout) {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, fields[0] == "printer" else { continue }
        let queue = String(fields[1])
        // A real queue name never contains a path separator.
        guard !queue.isEmpty, !queue.contains("/"), !queue.contains(":") else { continue }
        let attributes = run(ipptool, ["-tv", "ipp://localhost/printers/\(queue)",
                                       "get-printer-attributes.test"])
        guard attributes.ok,
              attributes.stdout.contains("printer-is-shared (boolean) = true") else { continue }
        // Only act when a per-user ACL is actually present.
        guard attributes.stdout.lowercased().contains("requesting-user-name-allowed") else {
            continue
        }
        let result = run(lpadmin, ["-p", queue, "-u", "allow:all"])
        if !result.stderr.isEmpty {
            appendLog(result.stderr.trimmingCharacters(in: .newlines), to: log)
        }
        if result.ok {
            appendLog("\(timestamp()) cleared user-ACL on '\(queue)' -> allow:all", to: log)
            changed = true
        } else {
            appendLog("\(timestamp()) FAILED on '\(queue)' (need admin/_lpadmin rights?)", to: log)
        }
    }
    if !changed {
        appendLog("\(timestamp()) checked: all shared queues already open", to: log)
    }
}

func runUSB() {
    let queues = run(lpstat, ["-v"])
    guard queues.ok else { exit(1) }
    let pids = run(pgrep, ["-x", "ippusbd"])
    guard pids.ok else { exit(0) }
    let allowedSerialCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    let commandPrefix = "/usr/libexec/ippusbd usb://HP%20Inc./HP%20Laser%20107a?serial="

    for field in pids.stdout.split(whereSeparator: \.isWhitespace) {
        let pid = String(field)
        let executable = run(ps, ["-p", pid, "-o", "comm="])
        guard executable.ok,
              executable.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                == "/usr/libexec/ippusbd" else { continue }
        let commandResult = run(ps, ["-p", pid, "-o", "args="])
        guard commandResult.ok else { continue }
        let command = commandResult.stdout.trimmingCharacters(in: .newlines)
        guard command.hasPrefix(commandPrefix),
              let serialSeparator = command.range(of: "?serial=") else { continue }
        let serial = String(command[serialSeparator.upperBound...])
        guard !serial.isEmpty, serial.allSatisfy({ allowedSerialCharacters.contains($0) }) else {
            continue
        }

        let expectedURI = "usb://HP/HP%20Laser%20103%20107%20108?serial=" + serial
        var configured = false
        for line in outputLines(queues.stdout) where line.hasPrefix("device for ") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.last.map(String.init) == expectedURI { configured = true }
        }
        guard configured else { continue }

        // Recheck the command before signalling, in case the process exited.
        let recheck = run(ps, ["-p", pid, "-o", "args="])
        guard recheck.ok,
              recheck.stdout.trimmingCharacters(in: .newlines) == command else { continue }
        guard run(kill, ["-TERM", pid]).ok else { exit(1) }
        print("Released the configured HP Laser 107a from IPP-over-USB.")
    }
    exit(0)
}

func runSelfTest() {
    signal(SIGTERM, handleTermination)
    signal(SIGINT, handleTermination)
    let name = "Printer Studio KH Helper Self Test"
    let txt = txtRecord(["txtvers=1"])
    var reference: DNSServiceRef?
    let error = txt.withUnsafeBytes { buffer -> DNSServiceErrorType in
        DNSServiceRegister(&reference, kDNSServiceFlagsNoAutoRename, 0,
                           name, "_ipp._tcp,_universal", nil, nil, UInt16(9).bigEndian,
                           UInt16(txt.count), buffer.baseAddress,
                           registrationCallback, nil)
    }
    guard error == kDNSServiceErr_NoError, let reference else {
        note("Self test could not register the service (Bonjour error \(error)).")
        exit(1)
    }
    registrations.append(reference)
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline { processResults(timeoutMilliseconds: 500) }
    withdrawAll()
    print("Self test registered and withdrew \(name).")
}

// MARK: - Entry point

let mode = CommandLine.arguments.dropFirst().first ?? ""
if clearOwnJobIfBundleIsGone(mode) { exit(0) }
switch mode {
case "all":
    runBridge(mode: "all", shareFixEvery: 60)
case "bridge":
    runBridge()
case "sharefix":
    runShareFix()
case "usb":
    runUSB()
case "list":
    runList()
case "selftest":
    runSelfTest()
default:
    note(usage)
    exit(2)
}
