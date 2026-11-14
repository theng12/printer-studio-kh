import Foundation

@main
struct TestListPresentation {
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

    static func makeEntry(_ message: String, kind: LogEntry.Kind = .info, date: Date = Date()) -> LogEntry {
        LogEntry(message, kind: kind, date: date)
    }

    static func main() {
        print("Running List Presentation Test Suite…\n")

        // List mode
        assertTest(PrinterListMode.defaultMode == .cards, "Default list mode is cards")
        assertTest(PrinterListMode.parse(nil) == .cards, "Nil stored mode defaults to cards")
        assertTest(PrinterListMode.parse("") == .cards, "Empty stored mode defaults to cards")
        assertTest(PrinterListMode.parse("bogus") == .cards, "Unknown stored mode defaults to cards")
        assertTest(PrinterListMode.parse("Cards") == .cards, "Non-matching case defaults to cards")
        assertTest(PrinterListMode.parse("cards") == .cards, "Stored cards parses as cards")
        assertTest(PrinterListMode.parse("table") == .table, "Stored table parses as table")
        assertTest(PrinterListMode.cards.rawValue == "cards", "Cards round-trips to raw value")
        assertTest(PrinterListMode.table.rawValue == "table", "Table round-trips to raw value")
        assertTest(PrinterListMode.parse(PrinterListMode.cards.rawValue) == .cards, "Cards raw value parses back")
        assertTest(PrinterListMode.parse(PrinterListMode.table.rawValue) == .table, "Table raw value parses back")

        // Warning grouping order and counts
        let a1 = AdviceItem(symbol: "lock.fill", tint: .danger, kind: .needsAttention, text: "Queue blocked")
        let s1 = AdviceItem(symbol: "clock", tint: .accent, kind: .suggestion, text: "Install watcher")
        let a2 = AdviceItem(symbol: "wifi.slash", tint: .warning, kind: .needsAttention, text: "Sharing off")
        let s2 = AdviceItem(symbol: "cable.connector", tint: .muted, kind: .suggestion, text: "Printer unplugged")
        let sections = WarningGrouper.group([a1, s1, a2, s2])
        assertTest(sections.count == 2, "Both warning sections present when both kinds exist")
        assertTest(sections[0].title == "Needs attention", "Needs attention section comes first")
        assertTest(sections[1].title == "Suggestions", "Suggestions section comes second")
        assertTest(sections[0].items.map(\.text) == ["Queue blocked", "Sharing off"],
                   "Needs attention keeps stable first-seen order")
        assertTest(sections[1].items.map(\.text) == ["Install watcher", "Printer unplugged"],
                   "Suggestions keep stable first-seen order")
        assertTest(sections[0].totalCount == 2 && sections[1].totalCount == 2, "Section totals count instances")

        // Duplicate collapse across non-adjacent identical warnings
        let dupA = AdviceItem(symbol: "lock.fill", tint: .danger, kind: .needsAttention, text: "Same problem")
        let mid = AdviceItem(symbol: "clock", tint: .accent, kind: .suggestion, text: "Different suggestion")
        let dupB = AdviceItem(symbol: "lock.fill", tint: .danger, kind: .needsAttention, text: "Same problem")
        let dupSections = WarningGrouper.group([dupA, mid, dupB])
        assertTest(dupSections.count == 2, "Duplicate collapse keeps both kind sections")
        assertTest(dupSections[0].items.count == 1, "Non-adjacent identical attention warnings collapse to one row")
        assertTest(dupSections[0].items[0].count == 2, "Collapsed attention warning carries count")
        assertTest(dupSections[0].items[0].displayText == "Same problem ×2", "Collapsed warning shows ×N")
        assertTest(dupSections[0].totalCount == 2, "Section total reflects collapsed instances")

        // Only one kind present
        let onlySuggestions = WarningGrouper.group([s1, s2])
        assertTest(onlySuggestions.count == 1 && onlySuggestions[0].title == "Suggestions",
                   "Only populated warning sections are returned")

        // Activity consecutive dedupe (input newest-first)
        let t0 = Date()
        let t1 = t0.addingTimeInterval(-1)
        let t2 = t0.addingTimeInterval(-2)
        let t3 = t0.addingTimeInterval(-3)
        let t4 = t0.addingTimeInterval(-4)
        let e0 = makeEntry("same", kind: .info, date: t0)
        let e1 = makeEntry("same", kind: .info, date: t1)
        let e2 = makeEntry("other", kind: .warning, date: t2)
        let e3 = makeEntry("same", kind: .info, date: t3)
        let e4 = makeEntry("same", kind: .info, date: t4)
        let digest = ActivityDeduper.condense([e0, e1, e2, e3, e4])
        assertTest(digest.count == 3, "Consecutive runs collapse but non-consecutive duplicates stay separate")
        assertTest(digest[0].message == "same" && digest[0].count == 2, "First consecutive run counted")
        assertTest(digest[0].timestamp == e0.timestamp, "Collapsed run keeps newest timestamp")
        assertTest(digest[0].displayMessage == "same ×2", "Collapsed activity shows ×N")
        assertTest(digest[1].message == "other" && digest[1].count == 1, "Middle different entry stands alone")
        assertTest(digest[2].message == "same" && digest[2].count == 2, "Later non-consecutive duplicate run counted separately")
        assertTest(ActivityDeduper.condense([]).isEmpty, "Empty activity condenses to empty")

        // Different kind breaks a consecutive run
        let k1 = makeEntry("same", kind: .info, date: t0)
        let k2 = makeEntry("same", kind: .error, date: t1)
        let kindDigest = ActivityDeduper.condense([k1, k2])
        assertTest(kindDigest.count == 2, "Same message with different kind is not consecutive-equal")

        // Unfinished jobs string dedupe
        let jobs = StringDeduper.dedupe(["job A", "job B", "job A", "job A", "job B", "job C"])
        assertTest(jobs.map(\.value) == ["job A", "job B", "job C"], "String dedupe keeps stable first-seen order")
        assertTest(jobs.map(\.count) == [3, 2, 1], "String dedupe carries counts")
        assertTest(jobs[0].display == "job A ×3" && jobs[2].display == "job C", "String dedupe display adds ×N only when repeated")

        // USB grouping counts
        let usb = [
            USBDevice(name: "HP Laser 107a", vendorID: "0x03f0", productID: "0xe82a"),
            USBDevice(name: "Other", vendorID: "0x1234", productID: "0x0001"),
            USBDevice(name: "HP Laser 107a", vendorID: "0x03f0", productID: "0xe82a"),
            USBDevice(name: "HP Laser 107a", vendorID: "0x03f0", productID: "0xe82b"),
        ]
        let grouped = USBDeduper.group(usb)
        assertTest(grouped.count == 3, "USB grouping collapses only identical name+vendor+product")
        assertTest(grouped[0].name == "HP Laser 107a" && grouped[0].productID == "0xe82a" && grouped[0].count == 2,
                   "Identical USB device grouped with count in first-seen position")
        assertTest(grouped[1].name == "Other" && grouped[1].count == 1, "Distinct USB device remains separate")
        assertTest(grouped[2].productID == "0xe82b" && grouped[2].count == 1, "Same name but different productID is separate")

        print("\nSummary: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
