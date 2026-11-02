import Foundation

/// A label (sticker) size, in millimetres.
///
/// These become `*PageSize` entries in a label printer's PPD. That is the only
/// way to influence what an iPhone offers: iOS has no custom-size field, and
/// the page-size list in its print dialog is exactly what the queue advertises
/// through IPP. So customising happens here, on the Mac, and the result shows
/// up on the phone.
struct StickerSize: Codable, Identifiable, Hashable {

    var id = UUID()
    var name: String
    var widthMM: Double
    var heightMM: Double
    /// Unchecked sizes stay in the list but are not written to any printer.
    var enabled = true

    // MARK: - PPD naming

    /// A safe label name without newlines, colons, slashes or quotes that could
    /// break PPD structure or inject PostScript commands.
    var sanitizedName: String {
        let stripped = name.filter { ch in
            ch.unicodeScalars.allSatisfy { (32...126).contains($0.value) } && ch != "\"" && ch != ":" && ch != "/" && ch != "\\"
        }.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "Custom" : stripped
    }

    /// The PPD option keyword.
    ///
    /// Prefixed with `psz` so our entries are unmistakable, which is what lets
    /// a re-apply remove the previous set cleanly instead of piling up
    /// duplicates. Millimetres are encoded at 0.1 mm resolution so that
    /// fractional sizes (38.1 mm) still produce a stable, collision-free name.
    var key: String {
        let slug = sanitizedName.lowercased().filter { $0.isLetter || $0.isNumber }
        let base = "psz\(Self.tenths(widthMM))x\(Self.tenths(heightMM))"
        return slug.isEmpty ? base : "\(base)-\(slug)"
    }

    /// The human-readable part of the PPD entry, shown by `lpoptions -l` and
    /// therefore by the iPhone.
    var label: String {
        "\(sanitizedName) (\(Self.mm(widthMM)) x \(Self.mm(heightMM)) mm)"
    }

    /// Dimensions in PostScript points, which is what a PPD stores.
    var widthPT: Double { widthMM * 72.0 / 25.4 }
    var heightPT: Double { heightMM * 72.0 / 25.4 }

    private static func tenths(_ mm: Double) -> String {
        guard mm.isFinite && mm > 0 else { return "0" }
        return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), mm * 10)
    }

    private static func mm(_ value: Double) -> String {
        guard value.isFinite && value > 0 else { return "0" }
        let rounded = (value * 10).rounded() / 10
        return String(format: rounded == rounded.rounded() ? "%.0f" : "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }

    // MARK: - Validation

    /// Whether this size is physically possible on a printer whose print limits
    /// are known in millimetres.
    func fits(minWidthMM: Double, maxWidthMM: Double, minHeightMM: Double, maxHeightMM: Double) -> Bool {
        widthMM.isFinite && heightMM.isFinite &&
        widthMM > 0 && heightMM > 0 &&
        widthMM >= minWidthMM && widthMM <= maxWidthMM &&
        heightMM >= minHeightMM && heightMM <= maxHeightMM
    }

    /// Backwards-compatible convenience where minimum dimensions are not constrained.
    func fits(maxWidthMM: Double, maxHeightMM: Double) -> Bool {
        fits(minWidthMM: 0, maxWidthMM: maxWidthMM, minHeightMM: 0, maxHeightMM: maxHeightMM)
    }
}

/// Where the user's size list is kept, and the sizes it starts with.
enum StickerSizeStore {

    static var url: URL {
        ShareFix.supportDirectory.appendingPathComponent("sticker-sizes.json")
    }

    /// Marker file recording that the one-time migration to defaults v2 has run.
    static var migrationMarkerURL: URL {
        ShareFix.supportDirectory.appendingPathComponent(".preset-migration-v2")
    }

    /// The new default presets requested by users (including portrait label orientations and sheet sizes).
    static let requestedDefaults: [StickerSize] = [
        StickerSize(name: "30x40", widthMM: 30, heightMM: 40),
        StickerSize(name: "50x70", widthMM: 50, heightMM: 70),
        StickerSize(name: "70x100", widthMM: 70, heightMM: 100),
        StickerSize(name: "A5", widthMM: 148, heightMM: 210),
        StickerSize(name: "A4", widthMM: 210, heightMM: 297),
    ]

    /// Fifteen sizes covering common thermal-label formats plus the five requested presets.
    ///
    /// Preserves original 10 defaults at their exact names and dimensions.
    static let defaults: [StickerSize] = [
        StickerSize(name: "Shipping 4x6", widthMM: 100, heightMM: 150),
        StickerSize(name: "Square", widthMM: 100, heightMM: 100),
        StickerSize(name: "Large", widthMM: 100, heightMM: 70),
        StickerSize(name: "Medium", widthMM: 70, heightMM: 50),
        StickerSize(name: "Address", widthMM: 60, heightMM: 40),
        StickerSize(name: "Small", widthMM: 50, heightMM: 30),
        StickerSize(name: "Jewelry", widthMM: 50, heightMM: 25),
        StickerSize(name: "Barcode", widthMM: 40, heightMM: 30),
        StickerSize(name: "Mini", widthMM: 38, heightMM: 25),
        StickerSize(name: "Cable", widthMM: 25, heightMM: 15),
    ] + requestedDefaults

    /// Appends new requested defaults to existing presets without duplicating matching dimensions or names.
    static func migrate(existing: [StickerSize]) -> [StickerSize] {
        var result = existing
        for preset in requestedDefaults {
            let alreadyPresent = result.contains {
                (abs($0.widthMM - preset.widthMM) < 0.1 && abs($0.heightMM - preset.heightMM) < 0.1) ||
                $0.name.trimmingCharacters(in: .whitespaces).lowercased() == preset.name.lowercased() ||
                $0.name.trimmingCharacters(in: .whitespaces).lowercased() == "\(preset.name)mm".lowercased()
            }
            if !alreadyPresent {
                result.append(preset)
            }
        }
        return result
    }

    static func load() -> [StickerSize] {
        load(from: url, markerURL: migrationMarkerURL, checkUserDefaults: true)
    }

    /// Loads presets from JSON. On first load of an existing install, performs a one-time
    /// migration appending the new presets while preserving user edits, custom sizes and removals.
    static func load(
        from fileURL: URL,
        markerURL: URL? = migrationMarkerURL,
        checkUserDefaults: Bool = true
    ) -> [StickerSize] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            if save(defaults, to: fileURL) {
                markMigrated(markerURL: markerURL, checkUserDefaults: checkUserDefaults)
            }
            return defaults
        }
        guard let data = try? Data(contentsOf: fileURL),
              let sizes = try? JSONDecoder().decode([StickerSize].self, from: data)
        else { return defaults }

        if isMigrated(markerURL: markerURL, checkUserDefaults: checkUserDefaults) {
            return sizes
        }

        let migrated = migrate(existing: sizes)
        if save(migrated, to: fileURL) {
            markMigrated(markerURL: markerURL, checkUserDefaults: checkUserDefaults)
        }
        return migrated
    }

    @discardableResult
    static func save(_ sizes: [StickerSize], to fileURL: URL = url) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sizes) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch { return false }
    }

    static func isMigrated(markerURL: URL?, checkUserDefaults: Bool = true) -> Bool {
        if let marker = markerURL, FileManager.default.fileExists(atPath: marker.path) {
            return true
        }
        if checkUserDefaults {
            return UserDefaults.standard.bool(forKey: "didMigratePaperPresetsV2")
        }
        return false
    }

    static func markMigrated(markerURL: URL?, checkUserDefaults: Bool = true) {
        if checkUserDefaults {
            UserDefaults.standard.set(true, forKey: "didMigratePaperPresetsV2")
        }
        if let marker = markerURL {
            try? FileManager.default.createDirectory(
                at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data().write(to: marker)
        }
    }
}
