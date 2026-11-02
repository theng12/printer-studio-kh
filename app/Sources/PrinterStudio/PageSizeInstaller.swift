import Foundation

/// Writes sticker sizes into label printers' PPDs, so an iPhone offers them.
///
/// Why a PPD and not something friendlier: the page-size list an iPhone shows
/// comes from the queue's IPP `media-supported` attribute, which CUPS derives
/// from the PPD's `*PageSize` entries. There is no per-job way to add a size
/// from iOS — the picker is the whole interface — so the sizes have to exist on
/// the queue before the phone ever connects.
///
/// The transformation is deliberately a pure function so it can be tested
/// without touching a real queue, and re-applying is idempotent: entries are
/// recognised by their `psz` prefix and replaced rather than appended.
enum PageSizeInstaller {

    /// Every entry we generate starts with this, which is how a re-apply knows
    /// what to remove. Chosen to collide with nothing a vendor ships.
    static let marker = "psz"

    /// Filters that mean "this queue drives a label printer". Used to pick
    /// sensible defaults in the interface; the user can still choose.
    static let labelFilterHints = [
        "rastertobarcode", "rastertosnail", "rastertolabel",
        "rastertodymo", "rastertozpl", "rastertoepl", "rastertotspl",
    ]

    static var queuePPDDirectory: String { "/etc/cups/ppd" }

    static func ppdPath(for queue: String) -> String {
        "\(queuePPDDirectory)/\(queue).ppd"
    }

    // MARK: - The transformation

    /// Returns `ppd` with the given sizes present and any previous set of ours
    /// removed. Pure: no filesystem, no privileges.
    static func transform(ppd: String, adding sizes: [StickerSize]) -> String {
        var lines = ppd.components(separatedBy: "\n")

        // 1. Drop whatever we added last time.
        lines.removeAll(where: isOurs)

        let usable = sizes.filter {
            $0.enabled &&
            $0.widthMM.isFinite && $0.heightMM.isFinite &&
            $0.widthMM > 0 && $0.heightMM > 0
        }

        // 2. PageSize entries, with the two localisation keys each of the
        //    vendor's own choices carries.
        if !usable.isEmpty {
            let entries = usable.map(pageSizeEntry)
                + usable.flatMap { translations(for: $0, ui: "PageSize") }
            if let at = indexOfClose(of: "*PageSize", in: lines) {
                lines.insert(contentsOf: entries, at: at)
            } else if let at = lines.firstIndex(where: { $0.hasPrefix("*OpenUI *PageRegion") }) {
                lines.insert(contentsOf: entries, at: at)
            } else {
                lines.append(contentsOf: entries)
            }

            // 2b. PageRegion. Missing these was a real defect: every PageSize
            //     needs one, and this PPD declares `*RequiresPageRegion All`.
            let regions = usable.map(pageRegionEntry)
                + usable.flatMap { translations(for: $0, ui: "PageRegion") }
            if let at = indexOfClose(of: "*PageRegion", in: lines) {
                lines.insert(contentsOf: regions, at: at)
            } else if let at = indexOfClose(of: "*PageSize", in: lines) {
                lines.insert(contentsOf: regions, at: at)
            }

            // 3. Matching ImageableArea entries. Without these CUPS falls back
            //    to a default area, which silently clips or offsets the label.
            let areas = usable.map(imageableAreaEntry)
            if let at = indexOfClose(of: "*ImageableArea", in: lines) {
                lines.insert(contentsOf: areas, at: at)
            } else if let last = lines.lastIndex(where: { $0.hasPrefix("*ImageableArea") }) {
                lines.insert(contentsOf: areas, at: last + 1)
            } else if let at = indexOfClose(of: "*PageSize", in: lines) {
                lines.insert(contentsOf: areas, at: at)
            }

            // 3b. PaperDimension. cupstestppd requires one for every PageSize,
            //     and the vendor ships them for its own three sizes, so ours
            //     need them too or the file is rejected outright.
            let dimensions = usable.map(paperDimensionEntry)
            if let last = lines.lastIndex(where: { $0.hasPrefix("*PaperDimension") }) {
                lines.insert(contentsOf: dimensions, at: last + 1)
            } else if let last = lines.lastIndex(where: { $0.hasPrefix("*ImageableArea") }) {
                lines.insert(contentsOf: dimensions, at: last + 1)
            }

            // 4. If a default no longer names a size that exists, point it at
            //    one that does, or CUPS rejects the PPD.
            lines = repairDefault("PageSize", in: lines)
            lines = repairDefault("PageRegion", in: lines)
            lines = repairDefault("ImageableArea", in: lines)
            lines = repairDefault("PaperDimension", in: lines)
        }

        return lines.joined(separator: "\n")
    }

    /// Whether a line is one of ours, so a re-apply replaces its own work
    /// instead of duplicating it.
    ///
    /// Covers the localised forms as well — `*zh_CN.PageSize psz…` — which an
    /// earlier version missed, so every re-apply piled up another copy of them.
    private static func isOurs(_ line: String) -> Bool {
        guard line.hasPrefix("*") else { return false }
        for key in ["PageSize", "PageRegion", "ImageableArea", "PaperDimension"] {
            if line.hasPrefix("*\(key) \(marker)") { return true }
            if line.contains(".\(key) \(marker)") { return true }
        }
        return false
    }

    /// The line index that closes the given UI block.
    ///
    /// PPDs write this two ways — `*CloseUI: *PageSize` and `*CloseUI *PageSize`
    /// — and the Xprinter PPD uses the colon form. An earlier version of this
    /// only knew the other one, never matched, and fell through to a fallback
    /// that happened to put the entries in a working place. It worked by luck.
    private static func indexOfClose(of ui: String, in lines: [String]) -> Int? {
        lines.firstIndex {
            $0.hasPrefix("*CloseUI: \(ui)") || $0.hasPrefix("*CloseUI \(ui)")
        }
    }

    static func pageSizeEntry(_ size: StickerSize) -> String {
        let w = points(size.widthPT)
        let h = points(size.heightPT)
        return "*PageSize \(size.key)/\(size.label): "
            + "\"<</PageSize[\(w) \(h)]/ImagingBBox null>>setpagedevice\""
    }

    static func imageableAreaEntry(_ size: StickerSize) -> String {
        let w = points(size.widthPT)
        let h = points(size.heightPT)
        return "*ImageableArea \(size.key)/\(size.label): \"0 0 \(w) \(h)\""
    }

    static func paperDimensionEntry(_ size: StickerSize) -> String {
        let w = points(size.widthPT)
        let h = points(size.heightPT)
        return "*PaperDimension \(size.key)/\(size.label): \"\(w) \(h)\""
    }

    /// PageRegion repeats the PageSize geometry. cupstestppd fails any PageSize
    /// without one, and this PPD sets `*RequiresPageRegion All: True`, so CUPS
    /// wants it at print time as well.
    static func pageRegionEntry(_ size: StickerSize) -> String {
        let w = points(size.widthPT)
        let h = points(size.heightPT)
        return "*PageRegion \(size.key)/\(size.label): "
            + "\"<</PageSize[\(w) \(h)]/ImagingBBox null>>setpagedevice\""
    }

    /// The localisation lines the vendor ships for every one of its own
    /// choices. The translation is empty — the vendor does the same — but
    /// cupstestppd counts the missing key as a failure, so they have to exist.
    ///
    /// `ui` is the bare name: `PageSize`, not `*PageSize`.
    static func translations(for size: StickerSize, ui: String) -> [String] {
        ["zh_CN", "zh_TW"].map { "*\($0).\(ui) \(size.key)/\(size.label): \"\"" }
    }

    /// PPDs want plain decimals, not scientific notation or trailing zeros.
    private static func points(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.2f", rounded)
    }

    /// `*DefaultPageSize` and `*DefaultPageRegion` must name a choice that
    /// exists, or CUPS rejects the PPD.
    private static func repairDefault(_ ui: String, in input: [String]) -> [String] {
        var lines = input
        let defaultPrefix = "*Default\(ui)"
        let choicePrefix = "*\(ui) "

        guard let defaultIndex = lines.firstIndex(where: { $0.hasPrefix(defaultPrefix) }),
              let colon = lines[defaultIndex].firstIndex(of: ":")
        else { return lines }

        let current = lines[defaultIndex][lines[defaultIndex].index(after: colon)...]
            .trimmingCharacters(in: .whitespaces)
        // Localisation lines start with `*zh_CN.`, so they cannot match the
        // choice prefix and are correctly ignored here.
        let available = lines
            .filter { $0.hasPrefix(choicePrefix) }
            .compactMap { line -> String? in
                let rest = line.dropFirst(choicePrefix.count)
                guard let slash = rest.firstIndex(of: "/") else { return nil }
                return String(rest[rest.startIndex..<slash])
            }

        guard !current.isEmpty, !available.contains(current), let fallback = available.first
        else { return lines }

        lines[defaultIndex] = "\(defaultPrefix): \(fallback)"
        return lines
    }

    // MARK: - Which queues are label printers

    struct LabelQueue {
        let name: String
        let model: String
        let ppdPath: String
        var sizeCount: Int
    }

    /// All queues, with those that look like label printers flagged.
    static func queues() -> [(queue: String, isLabel: Bool)] {
        let result = Shell.run(Tool.lpstat, ["-p"])
        return result.stdout
            .split(separator: "\n")
            .compactMap { line -> (String, Bool)? in
                // "printer NAME is idle..." — anchoring on "printer " skips the
                // warnings lpstat prints, which used to be read as queue names.
                guard line.hasPrefix("printer ") else { return nil }
                let name = line.dropFirst("printer ".count).prefix { !$0.isWhitespace }
                guard !name.isEmpty, !name.contains("/") else { return nil }
                return (String(name), isLabelPrinter(String(name)))
            }
    }

    static func isLabelPrinter(_ queue: String) -> Bool {
        guard let ppd = try? String(contentsOfFile: ppdPath(for: queue), encoding: .utf8)
        else { return false }
        let lowered = ppd.lowercased()
        return labelFilterHints.contains { lowered.contains($0) }
    }

    /// The advertised page sizes for a queue, as the iPhone sees them.
    static func currentSizes(queue: String) -> [String] {
        let result = Shell.run(Tool.lpoptions, ["-p", queue, "-l"])
        guard let line = result.stdout
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("PageSize/") || $0.hasPrefix("PageSize:") })
        else { return [] }

        guard let colon = line.firstIndex(of: ":") else { return [] }
        return line[line.index(after: colon)...]
            .split(separator: " ")
            .map { $0.hasPrefix("*") ? String($0.dropFirst()) : String($0) }
            .filter { !$0.isEmpty }
    }

    // MARK: - PPD Limits & Per-Printer Applicability

    struct PPDLimits: Equatable {
        let minWidthPT: Double
        let maxWidthPT: Double
        let minHeightPT: Double
        let maxHeightPT: Double

        var minWidthMM: Double { minWidthPT * 25.4 / 72.0 }
        var maxWidthMM: Double { maxWidthPT * 25.4 / 72.0 }
        var minHeightMM: Double { minHeightPT * 25.4 / 72.0 }
        var maxHeightMM: Double { maxHeightPT * 25.4 / 72.0 }
    }

    struct NativeSize: Equatable {
        let name: String
        let widthPT: Double
        let heightPT: Double

        var widthMM: Double { widthPT * 25.4 / 72.0 }
        var heightMM: Double { heightPT * 25.4 / 72.0 }
    }

    struct SizePlan: Equatable {
        enum SkipReason: Equatable, CustomStringConvertible {
            case disabled
            case invalidDimensions
            case exceedsMaxWidth(limitMM: Double)
            case belowMinWidth(limitMM: Double)
            case exceedsMaxHeight(limitMM: Double)
            case belowMinHeight(limitMM: Double)
            case duplicateOfNative(name: String)
            case noLimitsDeclared

            var description: String {
                switch self {
                case .disabled:
                    return "Disabled"
                case .invalidDimensions:
                    return "Invalid dimensions"
                case .exceedsMaxWidth(let limit):
                    return "Exceeds printer maximum width (\(Self.formatMM(limit)) mm)"
                case .belowMinWidth(let limit):
                    return "Below printer minimum width (\(Self.formatMM(limit)) mm)"
                case .exceedsMaxHeight(let limit):
                    return "Exceeds printer maximum height (\(Self.formatMM(limit)) mm)"
                case .belowMinHeight(let limit):
                    return "Below printer minimum height (\(Self.formatMM(limit)) mm)"
                case .duplicateOfNative(let name):
                    return "Already a native size on this printer (\(name))"
                case .noLimitsDeclared:
                    return "Printer PPD declares no custom page size limits"
                }
            }

            private static func formatMM(_ val: Double) -> String {
                let rounded = (val * 10).rounded() / 10
                return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
            }
        }

        struct SkippedSize: Equatable {
            let size: StickerSize
            let reason: SkipReason
        }

        let limits: PPDLimits?
        let nativeSizes: [NativeSize]
        let adding: [StickerSize]
        let skipped: [SkippedSize]
        let failureReason: String?

        var isApplicable: Bool { failureReason == nil && !adding.isEmpty }

        var summary: String {
            if let fail = failureReason { return fail }
            var parts: [String] = []
            if !adding.isEmpty {
                let names = adding.map(\.name).joined(separator: ", ")
                parts.append("Adding \(adding.count) size(s): \(names)")
            } else {
                parts.append("No sizes to add")
            }
            if !skipped.isEmpty {
                let skipSummary = skipped.map { "\($0.size.name) (\($0.reason))" }.joined(separator: "; ")
                parts.append("Skipped \(skipped.count): \(skipSummary)")
            }
            return parts.joined(separator: ". ")
        }
    }

    /// Extracts declared min and max page width and height from a PPD.
    ///
    /// Reads `*ParamCustomPageSize Width` and `Height`, and optionally `*MaxMediaWidth` / `*MaxMediaHeight`.
    /// Returns `nil` if the PPD does not declare bounds or has non-positive/invalid numbers.
    static func parseLimits(ppd: String) -> PPDLimits? {
        var minW: Double?
        var maxW: Double?
        var minH: Double?
        var maxH: Double?
        var widthCap: Double?
        var heightCap: Double?

        for line in ppd.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("*") else { continue }

            if trimmed.hasPrefix("*ParamCustomPageSize") {
                let rest = trimmed.dropFirst("*ParamCustomPageSize".count).trimmingCharacters(in: .whitespaces)
                let tokens = rest.split(whereSeparator: { $0.isWhitespace || $0 == ":" || $0 == "\"" })
                guard let first = tokens.first else { continue }
                let param = String(first).lowercased()
                let numbers = tokens.compactMap { Double($0) }
                let pair: (Double, Double)? = {
                    if numbers.count >= 3 {
                        return (numbers[numbers.count - 2], numbers[numbers.count - 1])
                    } else if numbers.count == 2 {
                        return (numbers[0], numbers[1])
                    }
                    return nil
                }()
                guard let (minVal, maxVal) = pair,
                      minVal >= 0, maxVal > 0, maxVal >= minVal, minVal.isFinite, maxVal.isFinite
                else { continue }

                if param == "width" {
                    minW = minVal
                    maxW = maxVal
                } else if param == "height" {
                    minH = minVal
                    maxH = maxVal
                }
            } else if trimmed.hasPrefix("*MaxMediaWidth") {
                let numbers = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == ":" || $0 == "\"" })
                    .compactMap { Double($0) }
                if let val = numbers.first, val > 0, val.isFinite {
                    widthCap = min(widthCap ?? val, val)
                }
            } else if trimmed.hasPrefix("*MaxMediaHeight") {
                let numbers = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == ":" || $0 == "\"" })
                    .compactMap { Double($0) }
                if let val = numbers.first, val > 0, val.isFinite {
                    heightCap = min(heightCap ?? val, val)
                }
            }
        }

        if let cap = widthCap, let width = maxW { maxW = min(width, cap) }
        if let cap = heightCap, let height = maxH { maxH = min(height, cap) }
        guard let wMin = minW, let wMax = maxW, let hMin = minH, let hMax = maxH,
              wMin >= 0, wMax > 0, wMax >= wMin, hMin >= 0, hMax > 0, hMax >= hMin
        else {
            return nil
        }
        return PPDLimits(minWidthPT: wMin, maxWidthPT: wMax, minHeightPT: hMin, maxHeightPT: hMax)
    }

    /// Extracts vendor-declared native page sizes from the PPD (excluding our `psz` sizes).
    static func parseNativeSizes(ppd: String) -> [NativeSize] {
        var results: [NativeSize] = []
        var seenNames = Set<String>()

        for line in ppd.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("*PaperDimension ") && !isOurs(trimmed) else { continue }

            let rest = trimmed.dropFirst("*PaperDimension ".count)
            guard let colon = rest.firstIndex(of: ":") else { continue }
            let namePart = rest[..<colon].trimmingCharacters(in: .whitespaces)
            let name = namePart.split(separator: "/").first.map(String.init) ?? namePart
            guard !name.isEmpty, !seenNames.contains(name) else { continue }

            let valuesPart = rest[rest.index(after: colon)...]
            let numbers = valuesPart.split(whereSeparator: { $0.isWhitespace || $0 == "\"" })
                .compactMap { Double($0) }
            guard numbers.count >= 2, numbers[0] > 0, numbers[1] > 0,
                  numbers[0].isFinite, numbers[1].isFinite
            else { continue }

            seenNames.insert(name)
            results.append(NativeSize(name: name, widthPT: numbers[0], heightPT: numbers[1]))
        }

        if results.isEmpty {
            for line in ppd.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("*PageSize ") && !isOurs(trimmed) else { continue }
                let rest = trimmed.dropFirst("*PageSize ".count)
                guard let colon = rest.firstIndex(of: ":") else { continue }
                let namePart = rest[..<colon].trimmingCharacters(in: .whitespaces)
                let name = namePart.split(separator: "/").first.map(String.init) ?? namePart
                guard !name.isEmpty, !seenNames.contains(name) else { continue }

                if let openBracket = rest.range(of: "PageSize[")?.upperBound,
                   let closeBracket = rest[openBracket...].firstIndex(of: "]") {
                    let dims = rest[openBracket..<closeBracket].split(separator: " ").compactMap { Double($0) }
                    if dims.count >= 2, dims[0] > 0, dims[1] > 0, dims[0].isFinite, dims[1].isFinite {
                        seenNames.insert(name)
                        results.append(NativeSize(name: name, widthPT: dims[0], heightPT: dims[1]))
                    }
                }
            }
        }
        return results
    }

    /// Whether a sticker size matches a native vendor page size by dimensions or canonical name.
    static func matchesNative(size: StickerSize, native: NativeSize) -> Bool {
        let wMatch = abs(size.widthPT - native.widthPT) <= 2.0
        let hMatch = abs(size.heightPT - native.heightPT) <= 2.0
        if wMatch && hMatch { return true }

        return false
    }

    /// Pure evaluation of which sizes can be safely applied to a printer PPD.
    static func plan(ppd: String, sizes: [StickerSize]) -> SizePlan {
        let limits = parseLimits(ppd: ppd)
        let native = parseNativeSizes(ppd: ppd)

        guard let lim = limits else {
            return SizePlan(
                limits: nil,
                nativeSizes: native,
                adding: [],
                skipped: sizes.map { SizePlan.SkippedSize(size: $0, reason: .noLimitsDeclared) },
                failureReason: "Printer PPD does not declare custom page size limits (ParamCustomPageSize)."
            )
        }

        var adding: [StickerSize] = []
        var skipped: [SizePlan.SkippedSize] = []

        for size in sizes {
            if !size.enabled {
                skipped.append(SizePlan.SkippedSize(size: size, reason: .disabled))
            } else if !size.widthMM.isFinite || !size.heightMM.isFinite || size.widthMM <= 0 || size.heightMM <= 0 {
                skipped.append(SizePlan.SkippedSize(size: size, reason: .invalidDimensions))
            } else if let matchedNative = native.first(where: { matchesNative(size: size, native: $0) }) {
                skipped.append(SizePlan.SkippedSize(size: size, reason: .duplicateOfNative(name: matchedNative.name)))
            } else if size.widthMM > lim.maxWidthMM + 0.1 {
                skipped.append(SizePlan.SkippedSize(size: size, reason: .exceedsMaxWidth(limitMM: lim.maxWidthMM)))
            } else if size.widthMM < lim.minWidthMM - 0.1 {
                skipped.append(SizePlan.SkippedSize(size: size, reason: .belowMinWidth(limitMM: lim.minWidthMM)))
            } else if size.heightMM > lim.maxHeightMM + 0.1 {
                skipped.append(SizePlan.SkippedSize(size: size, reason: .exceedsMaxHeight(limitMM: lim.maxHeightMM)))
            } else if size.heightMM < lim.minHeightMM - 0.1 {
                skipped.append(SizePlan.SkippedSize(size: size, reason: .belowMinHeight(limitMM: lim.minHeightMM)))
            } else {
                adding.append(size)
            }
        }

        let failureReason: String? = adding.isEmpty
            ? "None of the requested sizes fit within printer limits (width \(String(format: "%.1f", lim.minWidthMM))–\(String(format: "%.1f", lim.maxWidthMM)) mm, height \(String(format: "%.1f", lim.minHeightMM))–\(String(format: "%.1f", lim.maxHeightMM)) mm) without duplicating native sizes."
            : nil

        return SizePlan(
            limits: lim,
            nativeSizes: native,
            adding: adding,
            skipped: skipped,
            failureReason: failureReason
        )
    }

    /// Pure plan helper for a specific named queue.
    static func plan(queue: String, sizes: [StickerSize]) -> SizePlan {
        guard let ppd = try? String(contentsOfFile: ppdPath(for: queue), encoding: .utf8) else {
            return SizePlan(
                limits: nil,
                nativeSizes: [],
                adding: [],
                skipped: sizes.map { SizePlan.SkippedSize(size: $0, reason: .noLimitsDeclared) },
                failureReason: "Could not read PPD for \(queue)."
            )
        }
        return plan(ppd: ppd, sizes: sizes)
    }

    /// One-line human-readable summary of size applicability for a queue.
    static func queueSummary(queue: String, sizes: [StickerSize]) -> String {
        plan(queue: queue, sizes: sizes).summary
    }

    /// One-line human-readable summary of size applicability for a PPD string.
    static func queueSummary(ppd: String, sizes: [StickerSize]) -> String {
        plan(ppd: ppd, sizes: sizes).summary
    }

    /// The widest label a queue's PPD will accept, so the interface can say
    /// when a size the user typed is physically impossible.
    static func maxWidthMM(queue: String) -> Double? {
        guard let ppd = try? String(contentsOfFile: ppdPath(for: queue), encoding: .utf8) else {
            return nil
        }
        return parseLimits(ppd: ppd)?.maxWidthMM
    }

    // MARK: - Applying

    /// Rewrites the PPD of every chosen queue. Needs an administrator, because
    /// `/etc/cups/ppd` is root-owned and CUPS verifies it has not been tampered
    /// with by anyone else.
    static func apply(sizes: [StickerSize], to queues: [String]) -> CommandResult {
        guard !queues.isEmpty else {
            return .failure("No printers were selected.")
        }

        var payloads: [(queue: String, contents: String, plan: SizePlan)] = []
        var queueReports: [String] = []

        for queue in queues {
            let path = ppdPath(for: queue)
            guard let original = try? String(contentsOfFile: path, encoding: .utf8) else {
                return .failure("Could not read \(path). Is the printer installed?")
            }
            let queuePlan = plan(ppd: original, sizes: sizes)
            guard let limits = queuePlan.limits else {
                return .failure("Cannot apply sizes to \(queue): printer PPD does not declare custom page size limits (ParamCustomPageSize).")
            }
            guard !queuePlan.adding.isEmpty else {
                return .failure("Cannot apply sizes to \(queue): none of the enabled sizes fit this printer's declared limits "
                                + "(\(String(format: "%.1f", limits.minWidthMM))–\(String(format: "%.1f", limits.maxWidthMM)) mm wide, "
                                + "\(String(format: "%.1f", limits.minHeightMM))–\(String(format: "%.1f", limits.maxHeightMM)) mm high) "
                                + "without duplicating native sizes.")
            }

            let transformed = transform(ppd: original, adding: queuePlan.adding)
            payloads.append((queue, transformed, queuePlan))

            let addedNames = queuePlan.adding.map(\.name).joined(separator: ", ")
            let skipped = queuePlan.skipped.map { "\($0.size.name): \($0.reason)" }.joined(separator: "; ")
            queueReports.append("• \(queue): added \(queuePlan.adding.count) size(s) (\(addedNames)); skipped: \(skipped)")
        }

        // Validate before installing anything, so a bad entry cannot leave a
        // printer unusable.
        let staging = NSTemporaryDirectory() + "printer-studio-ppd-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: staging) }

        for payload in payloads {
            let staged = "\(staging)/\(payload.queue).ppd"
            try? payload.contents.write(toFile: staged, atomically: true, encoding: .utf8)

            let before = validationComplaints(of: ppdPath(for: payload.queue))
            let after = validationComplaints(of: staged)
            let introduced = after.subtracting(before)
            if !introduced.isEmpty {
                return .failure("Adding these sizes would make \(payload.queue)'s PPD invalid, "
                                + "so nothing was changed. New problems:\n"
                                + introduced.sorted().joined(separator: "\n"))
            }
        }

        // Now install, as root.
        var script = "set -e\n"
        for payload in payloads {
            let staged = "\(staging)/\(payload.queue).ppd"
            script += """
            /bin/cp /etc/cups/ppd/\(shellQuoted(payload.queue)).ppd \
            /etc/cups/ppd/\(shellQuoted(payload.queue)).ppd.printerstudio-backup 2>/dev/null || true
            /bin/cp '\(staged)' /etc/cups/ppd/\(shellQuoted(payload.queue)).ppd
            /usr/sbin/chown root:_lp /etc/cups/ppd/\(shellQuoted(payload.queue)).ppd
            /bin/chmod 600 /etc/cups/ppd/\(shellQuoted(payload.queue)).ppd

            """
        }
        // CUPS caches PPDs, so it has to be told to look again.
        let summaryText = queueReports.joined(separator: "\n")
        script += """
        /bin/launchctl kickstart -k system/org.cups.cupsd 2>/dev/null || /usr/bin/killall -HUP cupsd 2>/dev/null || true
        /bin/sleep 2
        printf '%s\\n' \(shellQuoted(summaryText))
        """

        return Shell.runAsAdministrator(
            script,
            prompt: "Printer Studio KH needs to add your sticker sizes to these printers.")
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The complaints cupstestppd makes about a PPD.
    ///
    /// Errors and warnings both count. Continuation lines ("REF: ...") are
    /// ignored; they describe the complaint above them.
    ///
    /// NOTE: no `-q` here. With `-q`, cupstestppd prints nothing at all, so an
    /// earlier version of this compared two empty sets and passed everything —
    /// a gate that could never fail, which is worse than no gate.
    private static func validationComplaints(of path: String) -> Set<String> {
        let result = Shell.run(Tool.cupstestppd, [path])
        return Set(
            result.combined
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("**FAIL**") || $0.hasPrefix("**WARN**") }
        )
    }

    /// Removes our entries, putting a queue back to the vendor's own list.
    static func remove(from queues: [String]) -> CommandResult {
        guard !queues.isEmpty else { return .failure("No printers were selected.") }

        var script = "set -e\n"
        for queue in queues {
            let path = ppdPath(for: queue)
            guard let original = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let stripped = transform(ppd: original, adding: [])
            let staged = NSTemporaryDirectory() + "printer-studio-reset-\(queue).ppd"
            try? stripped.write(toFile: staged, atomically: true, encoding: .utf8)
            script += """
            /bin/cp '\(staged)' \(shellQuoted(path))
            /usr/sbin/chown root:_lp \(shellQuoted(path))
            /bin/chmod 600 \(shellQuoted(path))

            """
        }
        script += """
        /bin/launchctl kickstart -k system/org.cups.cupsd 2>/dev/null || /usr/bin/killall -HUP cupsd 2>/dev/null || true
        /bin/sleep 2
        echo "Removed the custom sizes."
        """
        return Shell.runAsAdministrator(
            script,
            prompt: "Printer Studio KH needs to reset these printers to their default sizes.")
    }
}
