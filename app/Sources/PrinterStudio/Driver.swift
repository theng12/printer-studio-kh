import Foundation

/// Everything specific to the HP Laser 107a — detecting it on the USB bus and
/// knowing whether a driver is present to talk to it.
///
/// The printer is a rebadged Samsung SL-M2026: a QPDL (SPL2) device with no
/// macOS driver and no AirPrint. The supported path is the splix
/// `rastertoqpdl` CUPS filter plus the `laser10x.ppd` PPD.
enum Driver {

    /// Where we install our own copy of the splix filter.
    static let ourFilterDirectory = "/Library/Printers/PrinterStudio/bin"
    static var ourFilter: String { ourFilterDirectory + "/rastertoqpdl" }

    /// Where a system-installed copy might already be.
    static var filterSearchPaths: [String] {
        [
            ourFilter,
            "/usr/libexec/cups/filter/rastertoqpdl",
            "/usr/local/libexec/cups/filter/rastertoqpdl",
            "/opt/homebrew/libexec/cups/filter/rastertoqpdl",
        ]
    }

    static var installedFilter: String? {
        filterSearchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isFilterInstalled: Bool { installedFilter != nil }

    /// PPD locations we check for the HP Laser 10x / M2020 model.
    static var ppdSearchPaths: [String] {
        [
            "/Library/Printers/PPDs/Contents/Resources/laser10x.ppd",
            "/Library/Printers/PPDs/Contents/Resources/m2020.ppd",
            "/usr/share/cups/model/laser10x.ppd",
            "/opt/homebrew/share/cups/model/laser10x.ppd",
        ]
    }

    static var installedPPD: String? {
        ppdSearchPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    static var isPPDInstalled: Bool { installedPPD != nil }

    /// True when we can actually build a queue for the printer.
    static var isReady: Bool { isFilterInstalled && isPPDInstalled }

    // MARK: - USB

    /// Parses the IORegistry for printer-class USB devices.
    static func usbDevices() -> [USBDevice] {
        let result = Shell.run(Tool.ioreg, ["-p", "IOUSB", "-w0", "-l"])
        guard result.ok else { return [] }

        var devices: [USBDevice] = []
        var name: String?
        var vendor: String?
        var product: String?

        func flush() {
            if let name, let vendor, let product {
                devices.append(USBDevice(name: name, vendorID: vendor, productID: product))
            }
            name = nil
            vendor = nil
            product = nil
        }

        for raw in result.stdout.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("\"USB Product Name\"") {
                flush()
                name = quotedValue(line)
            } else if line.hasPrefix("\"idVendor\"") {
                vendor = hexValue(line)
            } else if line.hasPrefix("\"idProduct\"") {
                product = hexValue(line)
            }
        }
        flush()

        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static var connectedLaser107a: USBDevice? {
        usbDevices().first { $0.isLaser107a }
    }

    /// Any USB device that looks like a printer, even if we do not know it.
    static func unknownUSBPrinters() -> [USBDevice] {
        usbDevices().filter { device in
            let n = device.name.lowercased()
            return (n.contains("laser") || n.contains("printer") || n.contains("samsung")
                || n.contains("hp "))
                && !device.isLaser107a
        }
    }

    // MARK: - Interface descriptors

    /// One USB interface, as the device advertises it.
    ///
    /// This matters more than it looks. A printer-class interface (7/1) comes in
    /// several protocols, and they are not interchangeable:
    ///
    ///   * protocol 1 or 2 — classic unidirectional/bidirectional. Accepts a raw
    ///     printer stream, which is what a CUPS backend sends.
    ///   * protocol 4 — IPP-over-USB. The device expects HTTP framing and
    ///     **silently discards raw SPL/QPDL**. This is the failure mode where
    ///     the printer accepts a job and does nothing at all.
    ///
    /// A device may offer both as alternate settings of one interface, and macOS
    /// is reported to leave this family on the IPP-over-USB one.
    struct Interface: Identifiable, Hashable {
        var id: String { "\(productName)#\(number)#\(alternate)" }
        let productName: String
        let number: Int
        let interfaceClass: Int
        let subClass: Int
        let protocolNumber: Int
        let alternate: Int

        var isPrinterClass: Bool { interfaceClass == 7 && subClass == 1 }
        var isIPPOverUSB: Bool { isPrinterClass && protocolNumber == 4 }
        var isClassicPrinter: Bool { isPrinterClass && (protocolNumber == 1 || protocolNumber == 2) }

        var summary: String { "class \(interfaceClass)/\(subClass)/\(protocolNumber), alt \(alternate)" }

        var note: String? {
            if isIPPOverUSB { return "IPP-over-USB — expects HTTP, will DISCARD a raw print stream" }
            if isClassicPrinter { return "classic printer — accepts a raw print stream" }
            if interfaceClass == 7 { return "printer class, unusual protocol" }
            return nil
        }
    }

    /// Reads interface descriptors out of the IORegistry.
    ///
    /// These live on `IOUSBHostInterface` nodes, which `-p IOUSB` does not
    /// descend into, so this walks the class directly. The output is large
    /// (some unrelated property is enormous), hence the line-by-line filter
    /// rather than keeping it all.
    static func usbInterfaces() -> [Interface] {
        let result = Shell.run(Tool.ioreg, ["-r", "-c", "IOUSBHostInterface", "-w0", "-l"])
        guard result.ok else { return [] }

        var interfaces: [Interface] = []
        var node: [String: String] = [:]

        // Properties inside a node arrive in no fixed order — bInterfaceProtocol
        // and bAlternateSetting come *before* bInterfaceClass — so a node has to
        // be collected whole before it can be interpreted. Splitting on the node
        // header is the only reliable boundary. (Scanning for bInterfaceClass
        // instead also picks up copies embedded in the device's USB Device Info
        // dictionary, which inflates the count.)
        func flush() {
            defer { node = [:] }
            guard let classValue = node["bInterfaceClass"].flatMap(Int.init) else { return }
            interfaces.append(Interface(
                productName: node["USB Product Name"] ?? "unknown device",
                number: node["bInterfaceNumber"].flatMap(Int.init) ?? 0,
                interfaceClass: classValue,
                subClass: node["bInterfaceSubClass"].flatMap(Int.init) ?? 0,
                protocolNumber: node["bInterfaceProtocol"].flatMap(Int.init) ?? 0,
                alternate: node["bAlternateSetting"].flatMap(Int.init) ?? 0
            ))
        }

        // ioreg draws its tree with |, +, - and ` characters in the indentation,
        // so trimming whitespace alone leaves a leading "|" and every nested
        // interface gets skipped.
        let indentNoise = CharacterSet(charactersIn: " |+-`")

        for raw in result.stdout.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: indentNoise)

            if line.contains("<class IOUSBHostInterface") {
                flush()
                continue
            }
            guard line.hasPrefix("\""), let equals = line.range(of: " = ") else { continue }

            let key = String(line[line.startIndex..<equals.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            var value = String(line[equals.upperBound...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            node[key] = value
        }
        flush()

        return interfaces.sorted {
            ($0.productName, $0.number, $0.alternate) < ($1.productName, $1.number, $1.alternate)
        }
    }

    /// Interfaces belonging to the HP Laser 107a, if it is attached.
    static func laser107aInterfaces() -> [Interface] {
        guard let device = connectedLaser107a else { return [] }
        return usbInterfaces().filter { $0.productName == device.name }
    }

    private static func intValue(_ line: String, key: String) -> Int? {
        guard line.hasPrefix("\"\(key)\"") else { return nil }
        guard let equals = line.range(of: "= ") else { return nil }
        return Int(line[equals.upperBound...].trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Parsing helpers

    private static func quotedValue(_ line: String) -> String? {
        guard let first = line.range(of: "= \"") else { return nil }
        let rest = line[first.upperBound...]
        guard let end = rest.lastIndex(of: "\"") else { return nil }
        return String(rest[rest.startIndex..<end])
    }

    private static func hexValue(_ line: String) -> String? {
        guard let equals = line.range(of: "= ") else { return nil }
        let raw = line[equals.upperBound...].trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("0x") { return raw.lowercased() }
        if let decimal = Int(raw) { return String(format: "0x%04x", decimal) }
        return nil
    }
}
