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

    /// The PPD option keyword.
    ///
    /// Prefixed with `psz` so our entries are unmistakable, which is what lets
    /// a re-apply remove the previous set cleanly instead of piling up
    /// duplicates. Millimetres are encoded at 0.1 mm resolution so that
    /// fractional sizes (38.1 mm) still produce a stable, collision-free name.
    var key: String {
        let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let base = "psz\(Self.tenths(widthMM))x\(Self.tenths(heightMM))"
        return slug.isEmpty ? base : "\(base)-\(slug)"
    }

    /// The human-readable part of the PPD entry, shown by `lpoptions -l` and
    /// therefore by the iPhone.
    var label: String {
        "\(name) (\(Self.mm(widthMM)) x \(Self.mm(heightMM)) mm)"
    }

    /// Dimensions in PostScript points, which is what a PPD stores.
    var widthPT: Double { widthMM * 72.0 / 25.4 }
    var heightPT: Double { heightMM * 72.0 / 25.4 }

    private static func tenths(_ mm: Double) -> Int { Int((mm * 10).rounded()) }
    private static func mm(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    // MARK: - Validation

    /// Whether this size is physically possible on a printer whose maximum
    /// print width is `maxWidthMM`.
    func fits(maxWidthMM: Double, maxHeightMM: Double) -> Bool {
        widthMM > 0 && heightMM > 0 && widthMM <= maxWidthMM && heightMM <= maxHeightMM
    }
}

/// Where the user's size list is kept, and the sizes it starts with.
enum StickerSizeStore {

    static var url: URL {
        ShareFix.supportDirectory.appendingPathComponent("sticker-sizes.json")
    }

    /// Ten sizes covering the common thermal-label formats, including the three
    /// the user actually prints today (100x70, 70x50, 50x30).
    ///
    /// The vendor PPDs ship only 2x4, 4x4 and 4x6 inches, so without this list
    /// an iPhone offers three sizes that fit nothing.
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
    ]

    static func load() -> [StickerSize] {
        guard let data = try? Data(contentsOf: url),
              let sizes = try? JSONDecoder().decode([StickerSize].self, from: data),
              !sizes.isEmpty
        else { return defaults }
        return sizes
    }

    static func save(_ sizes: [StickerSize]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sizes) else { return }
        try? FileManager.default.createDirectory(
            at: ShareFix.supportDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
