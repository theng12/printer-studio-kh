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
