import Foundation

@main
struct TestPaperSizes {
    static var passed = 0
    static var failed = 0

    static func assertTest(_ condition: Bool, _ name: String) {
        if condition {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ FAIL: \(name)")
        }
    }

    /// Clean bounded thermal label printer PPD fixture for offline testing.
    static let thermalPPD = """
    *PPD-Adobe: "4.3"
    *FormatVersion: "4.3"
    *FileVersion: "1.0"
    *LanguageVersion: English
    *LanguageEncoding: ISOLatin1
    *PCFileName: "THERMAL.PPD"
    *Manufacturer: "Thermal"
    *Product: "(Thermal Label Printer)"
    *ModelName: "Thermal Label Printer"
    *ShortNickName: "Thermal Label"
    *NickName: "Thermal Label Printer"
    *PSVersion: "(3010.000) 0"
    *LanguageLevel: "3"
    *ColorDevice: False
    *DefaultColorSpace: Gray
    *FileSystem: False
    *Throughput: "1"
    *LandscapeOrientation: Plus90
    *TTRasterizer: Type42
    *cupsVersion: 2.0
    *cupsModelNumber: 0
    *cupsManualCopies: False
    *cupsFilter: "application/vnd.cups-raster 0 rastertolabel"

    *OpenUI *PageSize/Media Size: PickOne
    *OrderDependency: 10 AnySetup *PageSize
    *DefaultPageSize: w288h432
    *PageSize w288h432/4x6: "<</PageSize[288 432]/ImagingBBox null>>setpagedevice"
    *PageSize w288h288/4x4: "<</PageSize[288 288]/ImagingBBox null>>setpagedevice"
    *PageSize w144h288/2x4: "<</PageSize[144 288]/ImagingBBox null>>setpagedevice"
    *CloseUI: *PageSize

    *OpenUI *PageRegion/Media Size: PickOne
    *OrderDependency: 10 AnySetup *PageRegion
    *DefaultPageRegion: w288h432
    *PageRegion w288h432/4x6: "<</PageSize[288 432]/ImagingBBox null>>setpagedevice"
    *PageRegion w288h288/4x4: "<</PageSize[288 288]/ImagingBBox null>>setpagedevice"
    *PageRegion w144h288/2x4: "<</PageSize[144 288]/ImagingBBox null>>setpagedevice"
    *CloseUI: *PageRegion

    *DefaultImageableArea: w288h432
    *ImageableArea w288h432/4x6: "0 0 288 432"
    *ImageableArea w288h288/4x4: "0 0 288 288"
    *ImageableArea w144h288/2x4: "0 0 144 288"

    *DefaultPaperDimension: w288h432
    *PaperDimension w288h432/4x6: "288 432"
    *PaperDimension w288h288/4x4: "288 288"
    *PaperDimension w144h288/2x4: "144 288"

    *CustomPageSize True: "pop pop pop <</PageSize[5 -2 roll]/ImagingBBox null>>setpagedevice"
    *ParamCustomPageSize Width: 1 points 56.7 306.14
    *ParamCustomPageSize Height: 2 points 42.5 850.39
    *ParamCustomPageSize WidthOffset: 3 points 0 0
    *ParamCustomPageSize HeightOffset: 4 points 0 0
    *ParamCustomPageSize Orientation: 5 int 0 0
    *MaxMediaWidth: "306.14"
    *MaxMediaHeight: "850.39"
    """

    static func main() {
        print("Running Paper Presets & PPD Applicability Test Suite…\n")

        let projectRoot: String = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        let trashDir: String = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp"

        testExactPresets()
        testMigrationPreservingSavedData(trashDir: trashDir)
        testPPDLimitsParsing()
        testNativeSizeDeduplication(projectRoot: projectRoot)
        testWidthAndHeightLimits()
        testSanitizationAndSafety()
        testIdempotenceAndRollback()
        testPageGeometryAndCupstestppd(projectRoot: projectRoot, trashDir: trashDir)
        testPlanAndQueueSummaryAPI()

        print("\nSummary: \(passed) passed, \(failed) failed")
        if failed > 0 {
            exit(1)
        }
    }

    // MARK: - 1. Exact Presets

    static func testExactPresets() {
        print("--- 1. Exact Presets ---")
        let defaults = StickerSizeStore.defaults
        assertTest(defaults.count == 15, "Defaults list contains exactly 15 presets (10 original + 5 requested)")

        // Verify original 10 defaults retain exact names and dimensions
        let expectedOriginal: [(String, Double, Double)] = [
            ("Shipping 4x6", 100, 150),
            ("Square", 100, 100),
            ("Large", 100, 70),
            ("Medium", 70, 50),
            ("Address", 60, 40),
            ("Small", 50, 30),
            ("Jewelry", 50, 25),
            ("Barcode", 40, 30),
            ("Mini", 38, 25),
            ("Cable", 25, 15),
        ]
        for (i, expected) in expectedOriginal.enumerated() {
            let actual = defaults[i]
            assertTest(actual.name == expected.0 && actual.widthMM == expected.1 && actual.heightMM == expected.2,
                       "Original preset #\(i + 1) '\(expected.0)' has exact name and dimensions (\(expected.1)x\(expected.2) mm)")
        }

        // Verify requested presets with exact dimensions and orientations
        let p30x40 = defaults.first { $0.name == "30x40" }
        assertTest(p30x40 != nil && p30x40?.widthMM == 30 && p30x40?.heightMM == 40,
                   "Preset 30x40 exists with portrait orientation (30 x 40 mm)")

        let p50x70 = defaults.first { $0.name == "50x70" }
        assertTest(p50x70 != nil && p50x70?.widthMM == 50 && p50x70?.heightMM == 70,
                   "Preset 50x70 exists with portrait orientation (50 x 70 mm)")

        let p70x100 = defaults.first { $0.name == "70x100" }
        assertTest(p70x100 != nil && p70x100?.widthMM == 70 && p70x100?.heightMM == 100,
                   "Preset 70x100 exists with portrait orientation (70 x 100 mm)")

        let pA5 = defaults.first { $0.name == "A5" }
        assertTest(pA5 != nil && pA5?.widthMM == 148 && pA5?.heightMM == 210,
                   "Preset A5 exists with exact ISO dimensions (148 x 210 mm)")

        let pA4 = defaults.first { $0.name == "A4" }
        assertTest(pA4 != nil && pA4?.widthMM == 210 && pA4?.heightMM == 297,
                   "Preset A4 exists with exact ISO dimensions (210 x 297 mm)")

        assertTest(defaults.allSatisfy { $0.enabled }, "All default presets start enabled")
    }

    // MARK: - 2. Migration Preserving Saved Data

    static func testMigrationPreservingSavedData(trashDir: String) {
        print("\n--- 2. Migration Preserving Saved Data ---")

        // Simulate an existing v1 install: 10 presets with user customisations
        var v1Sizes = Array(StickerSizeStore.defaults.prefix(10))
        // User disabled Cable
        if let idx = v1Sizes.firstIndex(where: { $0.name == "Cable" }) {
            v1Sizes[idx].enabled = false
        }
        // User edited Small to 55x35
        if let idx = v1Sizes.firstIndex(where: { $0.name == "Small" }) {
            v1Sizes[idx].widthMM = 55
            v1Sizes[idx].heightMM = 35
        }
        // User removed Jewelry
        v1Sizes.removeAll(where: { $0.name == "Jewelry" })
        // User added a custom size
        v1Sizes.append(StickerSize(name: "Box Label", widthMM: 85, heightMM: 55, enabled: true))

        // Pure migration test
        let migrated = StickerSizeStore.migrate(existing: v1Sizes)
        assertTest(migrated.contains(where: { $0.name == "Box Label" && $0.widthMM == 85 }),
                   "Migration preserves custom user presets")
        assertTest(migrated.contains(where: { $0.name == "Small" && $0.widthMM == 55 && $0.heightMM == 35 }),
                   "Migration preserves user-edited dimensions on existing presets")
        assertTest(migrated.contains(where: { $0.name == "Cable" && !$0.enabled }),
                   "Migration preserves user's disabled choices")
        assertTest(!migrated.contains(where: { $0.name == "Jewelry" }),
                   "Migration does NOT resurrect previously removed presets")
        assertTest(migrated.contains(where: { $0.name == "30x40" && $0.widthMM == 30 && $0.heightMM == 40 }) &&
                   migrated.contains(where: { $0.name == "50x70" && $0.widthMM == 50 && $0.heightMM == 70 }) &&
                   migrated.contains(where: { $0.name == "70x100" && $0.widthMM == 70 && $0.heightMM == 100 }) &&
                   migrated.contains(where: { $0.name == "A5" && $0.widthMM == 148 && $0.heightMM == 210 }) &&
                   migrated.contains(where: { $0.name == "A4" && $0.widthMM == 210 && $0.heightMM == 297 }),
                   "Migration appends all 5 requested presets")

        // Persistence and second-load idempotence test
        let testDir = URL(fileURLWithPath: "\(trashDir)/migration-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        let jsonURL = testDir.appendingPathComponent("sticker-sizes.json")
        let markerURL = testDir.appendingPathComponent(".preset-migration-v2")

        // Save v1 data to disk
        StickerSizeStore.save(v1Sizes, to: jsonURL)

        // First load: triggers migration
        let loaded1 = StickerSizeStore.load(from: jsonURL, markerURL: markerURL, checkUserDefaults: false)
        assertTest(loaded1.count == v1Sizes.count + 5, "First load performs migration and appends new presets")
        assertTest(FileManager.default.fileExists(atPath: markerURL.path), "Migration marker was written to disk")

        // User deletes "30x40" after migration and saves
        var modified = loaded1
        modified.removeAll(where: { $0.name == "30x40" })
        StickerSizeStore.save(modified, to: jsonURL)

        let emptyURL = testDir.appendingPathComponent("empty.json")
        let emptyMarker = testDir.appendingPathComponent("empty.marker")
        StickerSizeStore.save([], to: emptyURL)
        _ = StickerSizeStore.load(from: emptyURL, markerURL: emptyMarker, checkUserDefaults: false)
        StickerSizeStore.save([], to: emptyURL)
        assertTest(StickerSizeStore.load(from: emptyURL, markerURL: emptyMarker, checkUserDefaults: false).isEmpty,
                   "Removing all presets remains empty after migration")
        let failedMarker = testDir.appendingPathComponent("failed.marker")
        _ = StickerSizeStore.load(from: testDir, markerURL: failedMarker, checkUserDefaults: false)
        assertTest(!FileManager.default.fileExists(atPath: failedMarker.path),
                   "Failed preset read does not falsely mark migration complete")

        // Second load: must NOT resurrect "30x40"
        let loaded2 = StickerSizeStore.load(from: jsonURL, markerURL: markerURL, checkUserDefaults: false)
        assertTest(!loaded2.contains(where: { $0.name == "30x40" }),
                   "Second load does NOT resurrect user-deleted presets across app restarts")
        assertTest(loaded2.contains(where: { $0.name == "50x70" }),
                   "Other new presets remain present on second load")
    }

    // MARK: - 3. PPD Limits Parsing

    static func testPPDLimitsParsing() {
        print("\n--- 3. PPD Limits Parsing ---")

        // Bounded thermal fixture
        let thermalLimits = PageSizeInstaller.parseLimits(ppd: thermalPPD)
        assertTest(thermalLimits != nil, "Thermal PPD limits parsed successfully")
        if let lim = thermalLimits {
            assertTest(abs(lim.minWidthMM - 20.0) < 0.2, "Thermal min width is ~20 mm (56.7 pt)")
            assertTest(abs(lim.maxWidthMM - 108.0) < 0.2, "Thermal max width is ~108 mm (306.14 pt)")
            assertTest(abs(lim.minHeightMM - 15.0) < 0.2, "Thermal min height is ~15 mm (42.5 pt)")
            assertTest(abs(lim.maxHeightMM - 300.0) < 0.2, "Thermal max height is ~300 mm (850.39 pt)")
        }

        // Sheet printer PPD snippet (HP 108w / Brother style)
        let sheetPPD = """
        *ParamCustomPageSize Width: 1 points 215 612
        *ParamCustomPageSize Height: 2 points 360 1009
        """
        let sheetLimits = PageSizeInstaller.parseLimits(ppd: sheetPPD)
        assertTest(sheetLimits != nil, "Sheet printer limits parsed successfully")
        if let lim = sheetLimits {
            assertTest(abs(lim.minWidthMM - 75.85) < 0.2, "Sheet min width is ~76 mm (215 pt)")
            assertTest(abs(lim.maxWidthMM - 215.9) < 0.2, "Sheet max width is ~216 mm (612 pt)")
            assertTest(abs(lim.minHeightMM - 127.0) < 0.2, "Sheet min height is 127 mm (360 pt)")
            assertTest(abs(lim.maxHeightMM - 355.9) < 0.3, "Sheet max height is ~356 mm (1009 pt)")
        }

        let zeroMin = "*MaxMediaWidth: 200\n*ParamCustomPageSize Width: 1 points 0 306\n*ParamCustomPageSize Height: 2 points 0 850"
        let zeroLimits = PageSizeInstaller.parseLimits(ppd: zeroMin)
        assertTest(zeroLimits?.minWidthPT == 0 && zeroLimits?.maxWidthPT == 200,
                   "Zero lower bounds accepted; MaxMediaWidth honored before ParamCustomPageSize")
        let sameName = StickerSize(name: "A4", widthMM: 30, heightMM: 40)
        let nativeA4 = PageSizeInstaller.NativeSize(name: "A4", widthPT: 595, heightPT: 842)
        assertTest(!PageSizeInstaller.matchesNative(size: sameName, native: nativeA4),
                   "Same name with different dimensions is not a native duplicate")

        // PPD without limits (splix laser10x without ParamCustomPageSize)
        let emptyPPD = "*PageSize A4/A4: \"...\""
        assertTest(PageSizeInstaller.parseLimits(ppd: emptyPPD) == nil,
                   "PPD without ParamCustomPageSize returns nil (no invented limits)")

        // Malformed limits (negative, NaN, min > max)
        let malformedNegative = "*ParamCustomPageSize Width: 1 points -50 612\n*ParamCustomPageSize Height: 2 points 360 1009"
        assertTest(PageSizeInstaller.parseLimits(ppd: malformedNegative) == nil,
                   "Negative dimension limit rejected")

        let malformedInverted = "*ParamCustomPageSize Width: 1 points 612 215\n*ParamCustomPageSize Height: 2 points 360 1009"
        assertTest(PageSizeInstaller.parseLimits(ppd: malformedInverted) == nil,
                   "Inverted min > max limit rejected")
    }

    // MARK: - 4. Native Size Deduplication

    static func testNativeSizeDeduplication(projectRoot: String) {
        print("\n--- 4. Native Size Deduplication ---")

        let laserPPDPath = "\(projectRoot)/vendor/splix/ppd/laser10x.ppd"
        guard let laserPPD = try? String(contentsOfFile: laserPPDPath, encoding: .utf8) else {
            assertTest(false, "Could not load vendor/splix/ppd/laser10x.ppd")
            return
        }

        let nativeSizes = PageSizeInstaller.parseNativeSizes(ppd: laserPPD)
        assertTest(!nativeSizes.isEmpty, "Parsed native sizes from vendor/splix/ppd/laser10x.ppd")

        let hasNativeA4 = nativeSizes.contains { $0.name == "A4" }
        let hasNativeA5 = nativeSizes.contains { $0.name == "A5" }
        assertTest(hasNativeA4 && hasNativeA5, "Vendor PPD natively contains A4 and A5 choices")

        let sizeA4 = StickerSize(name: "A4", widthMM: 210, heightMM: 297)
        let sizeA5 = StickerSize(name: "A5", widthMM: 148, heightMM: 210)
        let sizeLabel = StickerSize(name: "30x40", widthMM: 30, heightMM: 40)

        let a4Native = nativeSizes.first { $0.name == "A4" }!
        assertTest(PageSizeInstaller.matchesNative(size: sizeA4, native: a4Native),
                   "matchesNative identifies A4 as duplicate of vendor native A4")

        let a5Native = nativeSizes.first { $0.name == "A5" }!
        assertTest(PageSizeInstaller.matchesNative(size: sizeA5, native: a5Native),
                   "matchesNative identifies A5 as duplicate of vendor native A5")

        assertTest(!PageSizeInstaller.matchesNative(size: sizeLabel, native: a4Native),
                   "matchesNative does not match distinct label size to A4")

        // Plan on laser printer PPD: A4/A5 duplicate native; label has no limits declared
        let plan = PageSizeInstaller.plan(ppd: laserPPD, sizes: [sizeA4, sizeA5, sizeLabel])
        assertTest(plan.limits == nil, "Laser PPD has no declared custom limits")
        assertTest(plan.adding.isEmpty, "No sizes added to laser PPD without limits")
    }

    // MARK: - 5. Width and Height Limits

    static func testWidthAndHeightLimits() {
        print("\n--- 5. Width and Height Limits ---")

        let sizes: [StickerSize] = [
            StickerSize(name: "30x40", widthMM: 30, heightMM: 40),
            StickerSize(name: "50x70", widthMM: 50, heightMM: 70),
            StickerSize(name: "70x100", widthMM: 70, heightMM: 100),
            StickerSize(name: "A5", widthMM: 148, heightMM: 210),
            StickerSize(name: "A4", widthMM: 210, heightMM: 297),
            StickerSize(name: "Tiny", widthMM: 10, heightMM: 10),
            StickerSize(name: "TooTall", widthMM: 50, heightMM: 350),
            StickerSize(name: "DisabledSize", widthMM: 50, heightMM: 50, enabled: false),
        ]

        let plan = PageSizeInstaller.plan(ppd: thermalPPD, sizes: sizes)
        assertTest(plan.isApplicable, "Thermal plan is applicable")

        let addedNames = Set(plan.adding.map(\.name))
        assertTest(addedNames.contains("30x40"), "30x40 mm fits within thermal limits and is added")
        assertTest(addedNames.contains("50x70"), "50x70 mm fits within thermal limits and is added")
        assertTest(addedNames.contains("70x100"), "70x100 mm fits within thermal limits and is added")

        // A5 and A4 exceed maxWidth (108 mm)
        let a5Skip = plan.skipped.first { $0.size.name == "A5" }
        assertTest(a5Skip != nil, "A5 is skipped on thermal printer")
        if case .exceedsMaxWidth(let lim)? = a5Skip?.reason {
            assertTest(abs(lim - 108.0) < 0.2, "A5 skipped with exceedsMaxWidth reason naming limit (~108 mm)")
        } else {
            assertTest(false, "A5 should have .exceedsMaxWidth reason")
        }

        let a4Skip = plan.skipped.first { $0.size.name == "A4" }
        assertTest(a4Skip != nil, "A4 is skipped on thermal printer")
        if case .exceedsMaxWidth = a4Skip?.reason {
            assertTest(true, "A4 skipped with .exceedsMaxWidth reason")
        } else {
            assertTest(false, "A4 should have .exceedsMaxWidth reason")
        }

        // Tiny is below min width / min height
        let tinySkip = plan.skipped.first { $0.size.name == "Tiny" }
        if case .belowMinWidth = tinySkip?.reason {
            assertTest(true, "10x10 mm size skipped with .belowMinWidth reason")
        } else {
            assertTest(false, "Tiny should have .belowMinWidth reason")
        }

        // TooTall exceeds maxHeight (300 mm)
        let tooTallSkip = plan.skipped.first { $0.size.name == "TooTall" }
        if case .exceedsMaxHeight = tooTallSkip?.reason {
            assertTest(true, "350 mm height skipped with .exceedsMaxHeight reason")
        } else {
            assertTest(false, "TooTall should have .exceedsMaxHeight reason")
        }

        // Disabled size is skipped
        let disabledSkip = plan.skipped.first { $0.size.name == "DisabledSize" }
        assertTest(disabledSkip?.reason == .disabled, "Disabled size is skipped with .disabled reason")
    }

    // MARK: - 6. Sanitization and Safety

    static func testSanitizationAndSafety() {
        print("\n--- 6. Sanitization and Safety ---")

        // Malicious name with newlines, quotes, colons and PostScript injection attempt
        let malicious = StickerSize(
            name: "BadSize\"\n*PageSize Injected/Exploit: \"pop\"\n*CloseUI: *All",
            widthMM: 30,
            heightMM: 40
        )
        assertTest(!malicious.sanitizedName.contains("\n") &&
                   !malicious.sanitizedName.contains("\"") &&
                   !malicious.sanitizedName.contains(":") &&
                   !malicious.sanitizedName.contains("/"),
                   "sanitizedName removes quotes, colons, slashes and newlines")
        assertTest(malicious.key.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted) == nil,
                   "key contains only safe alphanumeric and hyphen characters")
        assertTest(!malicious.label.contains("\n") && !malicious.label.contains("\""),
                   "label contains no newlines or double quotes")

        let shellText = "Label $(printf injected) `printf bad` 'quoted' \"double\""
        let shellResult = Shell.run("/bin/sh", ["-c", "printf '%s' \(PageSizeInstaller.shellQuoted(shellText))"])
        assertTest(shellResult.ok && shellResult.stdout == shellText,
                   "Root summary quoting keeps label text literal without shell evaluation")
        let controls = StickerSize(name: "Label\u{0}\tName", widthMM: 30, heightMM: 40)
        assertTest(!controls.sanitizedName.contains("\u{0}") && !controls.sanitizedName.contains("\t"),
                   "PPD labels strip control characters")

        // Nonfinite dimensions
        let nanSize = StickerSize(name: "NanSize", widthMM: Double.nan, heightMM: 40)
        let infSize = StickerSize(name: "InfSize", widthMM: 30, heightMM: Double.infinity)
        let negSize = StickerSize(name: "NegSize", widthMM: -30, heightMM: 40)

        let plan = PageSizeInstaller.plan(ppd: thermalPPD, sizes: [nanSize, infSize, negSize])
        assertTest(plan.skipped.contains { $0.size.name == "NanSize" && $0.reason == .invalidDimensions },
                   "NaN dimensions skipped with .invalidDimensions")
        assertTest(plan.skipped.contains { $0.size.name == "InfSize" && $0.reason == .invalidDimensions },
                   "Infinity dimensions skipped with .invalidDimensions")
        assertTest(plan.skipped.contains { $0.size.name == "NegSize" && $0.reason == .invalidDimensions },
                   "Negative dimensions skipped with .invalidDimensions")

        // Verify transform never emits nan or inf into PPD output
        let transformed = PageSizeInstaller.transform(ppd: thermalPPD, adding: [nanSize, infSize, negSize])
        assertTest(!transformed.contains("nan") && !transformed.contains("inf") && !transformed.contains("psznan"),
                   "Pure transform never emits nonfinite values into PPD lines")
    }

    // MARK: - 7. Idempotence and Rollback

    static func testIdempotenceAndRollback() {
        print("\n--- 7. Idempotence and Rollback ---")

        let sizes = [
            StickerSize(name: "30x40", widthMM: 30, heightMM: 40),
            StickerSize(name: "50x70", widthMM: 50, heightMM: 70),
        ]

        let t1 = PageSizeInstaller.transform(ppd: thermalPPD, adding: sizes)
        assertTest(t1.contains("*PageSize psz300x400-30x40/30x40 (30 x 40 mm)"), "Transformed PPD contains 30x40 PageSize")
        assertTest(t1.contains("*PageSize psz500x700-50x70/50x70 (50 x 70 mm)"), "Transformed PPD contains 50x70 PageSize")

        // Idempotence: transforming the result again produces identical content
        let t2 = PageSizeInstaller.transform(ppd: t1, adding: sizes)
        assertTest(t1 == t2, "Transform is strictly idempotent (applying twice produces identical PPD)")

        // Rollback: transforming with adding: [] strips our additions cleanly
        let stripped = PageSizeInstaller.transform(ppd: t1, adding: [])
        assertTest(!stripped.contains("psz"), "Transform with empty array strips all custom psz entries")
        let t3 = PageSizeInstaller.transform(ppd: stripped, adding: sizes)
        assertTest(t3 == t1, "Re-applying after strip produces identical valid PPD")
    }

    // MARK: - 8. Page Geometry and cupstestppd

    static func testPageGeometryAndCupstestppd(projectRoot: String, trashDir: String) {
        print("\n--- 8. Page Geometry and cupstestppd ---")

        let sizes = [
            StickerSize(name: "30x40", widthMM: 30, heightMM: 40),
            StickerSize(name: "50x70", widthMM: 50, heightMM: 70),
            StickerSize(name: "70x100", widthMM: 70, heightMM: 100),
        ]

        let transformed = PageSizeInstaller.transform(ppd: thermalPPD, adding: sizes)

        // Verify exact point geometry consistency across PageSize, PageRegion, ImageableArea, PaperDimension
        for size in sizes {
            let wPT = (size.widthPT * 100).rounded() / 100
            let hPT = (size.heightPT * 100).rounded() / 100
            let wStr = wPT == wPT.rounded() ? String(Int(wPT)) : String(format: "%.2f", wPT)
            let hStr = hPT == hPT.rounded() ? String(Int(hPT)) : String(format: "%.2f", hPT)

            assertTest(transformed.contains("*PageSize \(size.key)/\(size.label): \"<</PageSize[\(wStr) \(hStr)]"),
                       "PageSize for \(size.name) has exact matching points [\(wStr) \(hStr)]")
            assertTest(transformed.contains("*PageRegion \(size.key)/\(size.label): \"<</PageSize[\(wStr) \(hStr)]"),
                       "PageRegion for \(size.name) has exact matching points [\(wStr) \(hStr)]")
            assertTest(transformed.contains("*ImageableArea \(size.key)/\(size.label): \"0 0 \(wStr) \(hStr)\""),
                       "ImageableArea for \(size.name) has exact matching bounds (0 0 \(wStr) \(hStr))")
            assertTest(transformed.contains("*PaperDimension \(size.key)/\(size.label): \"\(wStr) \(hStr)\""),
                       "PaperDimension for \(size.name) has exact matching dimensions (\(wStr) \(hStr))")
        }

        // Write PPD files to trashDir for cupstestppd validation
        let origThermalPath = "\(trashDir)/thermal-orig.ppd"
        let transformedThermalPath = "\(trashDir)/thermal-transformed.ppd"
        try? thermalPPD.write(toFile: origThermalPath, atomically: true, encoding: .utf8)
        try? transformed.write(toFile: transformedThermalPath, atomically: true, encoding: .utf8)

        let origComplaints = complaintsOf(origThermalPath)
        let transformedComplaints = complaintsOf(transformedThermalPath)
        let newComplaints = transformedComplaints.subtracting(origComplaints)
        assertTest(newComplaints.isEmpty, "Transformed thermal PPD introduces ZERO new cupstestppd complaints (\(newComplaints))")

        // Also test transforming splix laser10x.ppd
        let laserPPDPath = "\(projectRoot)/vendor/splix/ppd/laser10x.ppd"
        if let origLaser = try? String(contentsOfFile: laserPPDPath, encoding: .utf8) {
            let transformedLaser = PageSizeInstaller.transform(ppd: origLaser, adding: sizes)
            let transformedLaserPath = "\(trashDir)/laser10x-transformed.ppd"
            try? transformedLaser.write(toFile: transformedLaserPath, atomically: true, encoding: .utf8)

            let origLaserComplaints = complaintsOf(laserPPDPath)
            let newLaserComplaints = complaintsOf(transformedLaserPath).subtracting(origLaserComplaints)
            assertTest(newLaserComplaints.isEmpty, "Transformed laser10x PPD introduces ZERO new cupstestppd complaints")
        }
    }

    // MARK: - 9. Plan and Queue Summary API

    static func testPlanAndQueueSummaryAPI() {
        print("\n--- 9. Plan and Queue Summary API ---")

        let plan = PageSizeInstaller.plan(ppd: thermalPPD, sizes: StickerSizeStore.defaults)
        assertTest(plan.isApplicable, "Plan for default sizes on thermal printer is applicable")
        assertTest(plan.summary.contains("Adding"), "Plan summary describes added sizes")
        assertTest(plan.summary.contains("Skipped"), "Plan summary describes skipped sizes with reasons")

        let summary = PageSizeInstaller.queueSummary(ppd: thermalPPD, sizes: StickerSizeStore.defaults)
        assertTest(!summary.isEmpty && summary.contains("Adding"), "queueSummary returns informative preview")
    }

    private static func complaintsOf(_ path: String) -> Set<String> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/cupstestppd")
        task.arguments = [path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return Set(
            text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("**FAIL**") || $0.hasPrefix("**WARN**") }
        )
    }
}
