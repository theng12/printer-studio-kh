import Foundation

// MARK: - Printer

struct Printer: Identifiable, Hashable {
    var id: String { name }
    let name: String
    var description: String = ""
    var displayName: String { description.isEmpty ? name : description }
    var state: String = "unknown"        // idle | printing | stopped
    var enabled: Bool = true
    var accepting: Bool = true
    var deviceURI: String = ""
    var makeAndModel: String = ""
    var isShared: Bool = false
    var hasUserACL: Bool = false

    var isIdle: Bool { state.lowercased().contains("idle") }
    var isPrinting: Bool { state.lowercased().contains("printing") }
    var isStopped: Bool { !enabled || state.lowercased().contains("stopped") }

    var transport: Transport {
        if deviceURI.hasPrefix("usb://") { return .usb }
        if deviceURI.hasPrefix("dnssd://") { return .bonjour }
        if deviceURI.hasPrefix("ipp://") || deviceURI.hasPrefix("ipps://") { return .ipp }
        if deviceURI.hasPrefix("socket://") { return .socket }
        if deviceURI.hasPrefix("lpd://") { return .lpd }
        if deviceURI.isEmpty { return .unknown }
        return .other
    }

    enum Transport: String {
        case usb = "USB"
        case bonjour = "Bonjour"
        case ipp = "IPP"
        case socket = "Network"
        case lpd = "LPD"
        case other = "Other"
        case unknown = "Unknown"

        var symbol: String {
            switch self {
            case .usb: return "cable.connector"
            case .bonjour, .ipp, .socket, .lpd: return "wifi"
            case .other, .unknown: return "questionmark.circle"
            }
        }
    }

    /// A short, friendly version of the device URI for display.
    var friendlyLocation: String {
        guard !deviceURI.isEmpty else { return "Not configured" }
        switch transport {
        case .usb:
            let rest = deviceURI.replacingOccurrences(of: "usb://", with: "")
            let withoutQuery = rest.split(separator: "?").first.map(String.init) ?? rest
            let decoded = withoutQuery.removingPercentEncoding ?? withoutQuery
            return "USB · " + decoded
        case .bonjour:
            // dnssd://Name%20Here._ipp._tcp.local./?uuid=...
            let rest = deviceURI.replacingOccurrences(of: "dnssd://", with: "")
            let host = rest.split(separator: "/").first.map(String.init) ?? rest
            let cleaned = host.split(separator: ".").first.map(String.init) ?? host
            return "Network · " + (cleaned.removingPercentEncoding ?? cleaned)
        case .ipp:
            // ipps://Name._ipps._tcp.local./ — show the advertised name, not the URI.
            let rest = deviceURI
                .replacingOccurrences(of: "ipps://", with: "")
                .replacingOccurrences(of: "ipp://", with: "")
            let raw = rest.split(separator: "/").first.map(String.init) ?? rest
            var name = raw.removingPercentEncoding ?? raw
            if let range = name.range(of: "._") { name = String(name[..<range.lowerBound]) }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "./"))
            return "Network · " + (name.isEmpty ? displayName : name)
        default:
            return deviceURI
        }
    }

    /// True when the queue is shared to the LAN but a per-user ACL is
    /// pinning it shut — the exact condition that causes other Macs to
    /// report "Job held for authentication".
    var isHeldShut: Bool { isShared && hasUserACL }
}

// MARK: - USB device

struct USBDevice: Identifiable, Hashable {
    var id: String { "\(vendorID):\(productID):\(name)" }
    let name: String
    let vendorID: String
    let productID: String

    /// HP Laser 107a / Samsung SL-M2026 family.
    static let laser107aVendor = "0x03f0"
    static let laser107aProducts: Set<String> = ["0xe82a", "0xe82b", "0xe82c"]

    var isLaser107a: Bool {
        vendorID.lowercased() == Self.laser107aVendor
            && Self.laser107aProducts.contains(productID.lowercased())
    }
}

// MARK: - Activity log

struct LogEntry: Identifiable, Hashable {
    enum Kind: String {
        case info, success, warning, error

        var symbol: String {
            switch self {
            case .info: return "info.circle"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
    }

    let id = UUID()
    let date: Date
    let kind: Kind
    let message: String

    init(_ message: String, kind: Kind = .info, date: Date = Date()) {
        self.message = message
        self.kind = kind
        self.date = date
    }

    var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
