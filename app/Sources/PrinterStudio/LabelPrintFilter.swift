import Foundation

/// Per-PPD routing for the two legacy label drivers, without a global MIME rule.
enum LabelPrintFilter {
    static let directory = "/Library/Printers/PrinterStudio/Filters"
    static let begin = "*% Printer Studio KH label route begin"
    static let end = "*% Printer Studio KH label route end"
    static let files = ["urftopdf", "label-options", "label-urf", "label-pdf"]

    static func vendor(in ppd: String) -> String? {
        let models = ppd.components(separatedBy: .newlines).filter {
            $0.hasPrefix("*ModelName:") || $0.hasPrefix("*ShortNickName:")
        }.compactMap { $0.split(separator: "\"").dropFirst().first.map(String.init) }
        if models.contains("TSC TTP-244 Pro"),
           ppd.contains("*cupsFilter: \"application/vnd.cups-raster 0 /Library/Printers/TSC/Filter/rastertobarcodetspl\"") {
            return "/Library/Printers/TSC/Filter/rastertobarcodetspl"
        }
        if models.contains("XP-D463B"),
           ppd.contains("*cupsFilter: \"application/vnd.cups-raster 0 rastertosnailtspl-xprinter\"") {
            return "rastertosnailtspl-xprinter"
        }
        return nil
    }

    static func transform(ppd: String) -> String? {
        guard let vendor = vendor(in: ppd) else { return nil }
        var lines: [String] = []
        var ours = false
        for line in ppd.components(separatedBy: .newlines) {
            if line == begin { ours = true; continue }
            if line == end { ours = false; continue }
            if !ours { lines.append(line) }
        }
        // Unknown filter2 routes must not be silently replaced.
        guard !ours, !lines.contains(where: { $0.hasPrefix("*cupsFilter2:") }) else { return nil }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n" + """
        \(begin)
        *PrinterStudioVendorFilter: "\(vendor)"
        *cupsFilter2: "image/urf application/vnd.cups-raw 0 \(directory)/label-urf"
        *cupsFilter2: "application/pdf application/vnd.cups-raw 0 \(directory)/label-pdf"
        *cupsFilter2: "application/vnd.cups-raster application/vnd.cups-raw 0 \(vendor)"
        \(end)

        """
    }

    static var payloadDirectory: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("label-filters", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("urftopdf").path) ? url : nil
    }

    static func payloadsMatch(_ source: URL) -> Bool {
        files.allSatisfy { name in
            let bundledName = name.hasPrefix("label-") && name != "label-options" ? "label-filter" : name
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            guard let expected = try? Data(contentsOf: source.appendingPathComponent(bundledName)),
                  let installed = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  let mode = attributes[.posixPermissions] as? NSNumber,
                  mode.intValue & 0o022 == 0, FileManager.default.isExecutableFile(atPath: path) else { return false }
            return expected == installed
        }
    }

    static func needsSetup(printers: [Printer]) -> Bool {
        let ppds = printers.compactMap { PageSizeInstaller.readPPD(queue: $0.name) }
            .filter { vendor(in: $0) != nil }
        guard !ppds.isEmpty else { return false }
        guard let source = payloadDirectory, payloadsMatch(source) else { return true }
        return ppds.contains { transform(ppd: $0) != $0 }
    }

    static func installIfNeeded() -> CommandResult {
        let printers = CUPS.listPrinters()
        var targets: [(String, String, String)] = []
        for printer in printers {
            guard let ppd = PageSizeInstaller.readPPD(queue: printer.name), let driver = vendor(in: ppd) else { continue }
            guard printer.state != "printing" else {
                return .failure("Wait for \(printer.displayName) to finish its current job, then set up label printing again.")
            }
            guard printer.name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
                return .failure("This label queue has an unsupported identifier. Its driver was left unchanged.")
            }
            let driverPath = driver.hasPrefix("/") ? driver : "/usr/libexec/cups/filter/\(driver)"
            guard FileManager.default.isExecutableFile(atPath: driverPath) else {
                return .failure("The vendor label driver is missing: \(driverPath). Install that printer's driver first.")
            }
            guard let changed = transform(ppd: ppd) else {
                return .failure("\(printer.displayName) has another filter route. Its driver was left unchanged.")
            }
            targets.append((printer.name, ppd, changed))
        }
        guard !targets.isEmpty else {
            return CommandResult(status: 0, stdout: "No supported legacy label queues need setup.", stderr: "")
        }
        guard let source = payloadDirectory else { return .failure("The label conversion filters are missing from this app.") }
        if payloadsMatch(source), targets.allSatisfy({ $0.1 == $0.2 }) {
            return CommandResult(status: 0, stdout: "Label printing is already set up.", stderr: "")
        }
        let id = UUID().uuidString
        let stage = ShareFix.supportDirectory.appendingPathComponent("_trash/label-route-\(id)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            for (index, target) in targets.enumerated() {
                try target.1.write(to: stage.appendingPathComponent("\(index)-before.ppd"), atomically: true, encoding: .utf8)
                try target.2.write(to: stage.appendingPathComponent("\(index)-after.ppd"), atomically: true, encoding: .utf8)
                let before = PageSizeInstaller.validationComplaints(of: stage.appendingPathComponent("\(index)-before.ppd").path, ignoreFilterFiles: true)
                let after = PageSizeInstaller.validationComplaints(of: stage.appendingPathComponent("\(index)-after.ppd").path, ignoreFilterFiles: true)
                guard after.subtracting(before).isEmpty else {
                    return .failure("The label route would introduce PPD validation errors for \(target.0). Nothing was installed.")
                }
            }
        } catch { return .failure("Could not stage label driver updates: \(error.localizedDescription)") }
        for name in files {
            let bundledName = name.hasPrefix("label-") && name != "label-options" ? "label-filter" : name
            guard FileManager.default.isExecutableFile(atPath: source.appendingPathComponent(bundledName).path) else {
                return .failure("Missing executable label payload: \(bundledName)")
            }
        }
        return Shell.runAsAdministrator(
            installScript(source: source, stage: stage, targets: targets.map { $0.0 }, id: id),
            prompt: "Printer Studio KH needs to set up iPhone printing for your label printers.")
    }

    static func installScript(source: URL, stage: URL, targets: [String], id: String) -> String {
        let quote = PageSizeInstaller.shellQuoted
        var script = "set -e\n"
        script += "/bin/mkdir -p \(quote(directory)) \(quote(directory + "/../_trash/" + id))\n"
        for name in files {
            let bundledName = name.hasPrefix("label-") && name != "label-options" ? "label-filter" : name
            let input = source.appendingPathComponent(bundledName).path
            let output = directory + "/" + name
            script += """
            if [ -e \(quote(output)) ]; then /bin/cp -p \(quote(output)) \(quote(directory + "/../_trash/" + id + "/" + name)); fi
            /usr/bin/install -o root -g wheel -m 555 \(quote(input)) \(quote(output))
            /usr/bin/cmp -s \(quote(input)) \(quote(output))

            """
            if name == "urftopdf" || name == "label-options" {
                script += "/usr/bin/codesign --verify --strict \(quote(output))\n"
            }
        }
        script += "restore_ppds() {\n"
        for (index, target) in targets.enumerated() {
            script += "\(quote(Tool.lpadmin)) -p \(quote(target)) -P \(quote(stage.appendingPathComponent("\(index)-before.ppd").path)) || true\n"
        }
        script += "printf '%s\\n' 'Label setup failed; previous PPDs were restored where possible.' >&2\n}\ntrap restore_ppds ERR\n"
        for (index, target) in targets.enumerated() {
            let original = "/etc/cups/ppd/\(target).ppd"
            script += """
            if [ ! -e \(quote(original + ".printerstudio-label-backup")) ]; then /bin/cp -p \(quote(original)) \(quote(original + ".printerstudio-label-backup")); fi
            \(quote(Tool.lpadmin)) -p \(quote(target)) -P \(quote(stage.appendingPathComponent("\(index)-after.ppd").path))

            """
        }
        script += "trap - ERR\nprintf '%s\\n' 'Label conversion installed. Previous PPDs and filters are recoverable.'\n"
        return script
    }
}
