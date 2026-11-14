import Foundation

/// Pure, testable presentation helpers for the Fleet UI lists.

enum PrinterListMode: String, CaseIterable {
    case cards
    case table

    static let storageKey = "printersListMode"
    static let defaultMode: PrinterListMode = .cards

    static func parse(_ raw: String?) -> PrinterListMode {
        guard let raw, let mode = PrinterListMode(rawValue: raw) else { return .defaultMode }
        return mode
    }
}

enum WarningKind: String {
    case needsAttention
    case suggestion
}

enum AdviceTint: String {
    case danger
    case warning
    case accent
    case muted
    case success
}

struct AdviceItem {
    let symbol: String
    let tint: AdviceTint
    let kind: WarningKind
    let text: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(symbol: String, tint: AdviceTint, kind: WarningKind, text: String,
         actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.tint = tint
        self.kind = kind
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }
}

struct DedupedAdvice: Identifiable {
    let id: String
    let symbol: String
    let tint: AdviceTint
    let kind: WarningKind
    let text: String
    let actionTitle: String?
    let action: (() -> Void)?
    let count: Int

    var displayText: String { count > 1 ? "\(text) ×\(count)" : text }
}

struct WarningSection: Identifiable {
    let id: String
    let kind: WarningKind
    let title: String
    let items: [DedupedAdvice]

    /// Total warning instances represented in this section.
    var totalCount: Int { items.reduce(0) { $0 + $1.count } }
}

enum WarningGrouper {
    /// Groups advice by kind and dedupes identical advice lines (by text) within
    /// each kind in stable first-seen order, carrying a count. Returns only
    /// sections that contain items, in "Needs attention" then "Suggestions" order.
    static func group(_ items: [AdviceItem]) -> [WarningSection] {
        var attention: [DedupedAdvice] = []
        var attentionIndex: [String: Int] = [:]
        var suggestions: [DedupedAdvice] = []
        var suggestionIndex: [String: Int] = [:]

        for item in items {
            switch item.kind {
            case .needsAttention:
                if let idx = attentionIndex[item.text] {
                    let existing = attention[idx]
                    attention[idx] = DedupedAdvice(id: existing.id, symbol: existing.symbol, tint: existing.tint,
                                                   kind: existing.kind, text: existing.text,
                                                   actionTitle: existing.actionTitle, action: existing.action,
                                                   count: existing.count + 1)
                } else {
                    attentionIndex[item.text] = attention.count
                    attention.append(DedupedAdvice(id: "attention-\(attention.count)", symbol: item.symbol, tint: item.tint,
                                                   kind: item.kind, text: item.text,
                                                   actionTitle: item.actionTitle, action: item.action,
                                                   count: 1))
                }
            case .suggestion:
                if let idx = suggestionIndex[item.text] {
                    let existing = suggestions[idx]
                    suggestions[idx] = DedupedAdvice(id: existing.id, symbol: existing.symbol, tint: existing.tint,
                                                     kind: existing.kind, text: existing.text,
                                                     actionTitle: existing.actionTitle, action: existing.action,
                                                     count: existing.count + 1)
                } else {
                    suggestionIndex[item.text] = suggestions.count
                    suggestions.append(DedupedAdvice(id: "suggestion-\(suggestions.count)", symbol: item.symbol, tint: item.tint,
                                                     kind: item.kind, text: item.text,
                                                     actionTitle: item.actionTitle, action: item.action,
                                                     count: 1))
                }
            }
        }

        var sections: [WarningSection] = []
        if !attention.isEmpty {
            sections.append(WarningSection(id: "needsAttention", kind: .needsAttention,
                                           title: "Needs attention", items: attention))
        }
        if !suggestions.isEmpty {
            sections.append(WarningSection(id: "suggestions", kind: .suggestion,
                                           title: "Suggestions", items: suggestions))
        }
        return sections
    }
}

struct ActivityDigest: Identifiable {
    let id: UUID
    let kind: LogEntry.Kind
    let message: String
    let timestamp: String
    let count: Int

    var displayMessage: String { count > 1 ? "\(message) ×\(count)" : message }
}

enum ActivityDeduper {
    /// Groups consecutive identical entries (same message and kind) into one row
    /// with a count and the newest timestamp. Non-consecutive duplicates stay
    /// separate. The input is expected newest-first, as stored in AppState.
    static func condense(_ entries: [LogEntry]) -> [ActivityDigest] {
        guard !entries.isEmpty else { return [] }
        var result: [ActivityDigest] = []
        var current = entries[0]
        var count = 1
        for i in 1..<entries.count {
            let entry = entries[i]
            if entry.message == current.message && entry.kind == current.kind {
                count += 1
            } else {
                result.append(ActivityDigest(id: current.id, kind: current.kind,
                                             message: current.message, timestamp: current.timestamp,
                                             count: count))
                current = entry
                count = 1
            }
        }
        result.append(ActivityDigest(id: current.id, kind: current.kind,
                                     message: current.message, timestamp: current.timestamp,
                                     count: count))
        return result
    }
}

struct CountedString: Identifiable, Hashable {
    let value: String
    let count: Int
    var id: String { value }
    var display: String { count > 1 ? "\(value) ×\(count)" : value }
}

enum StringDeduper {
    /// Dedupes identical strings in stable first-seen order, carrying a count.
    static func dedupe(_ values: [String]) -> [CountedString] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for value in values {
            if let existing = counts[value] {
                counts[value] = existing + 1
            } else {
                order.append(value)
                counts[value] = 1
            }
        }
        return order.map { CountedString(value: $0, count: counts[$0] ?? 1) }
    }
}

struct USBGroup: Identifiable {
    let id: String
    let name: String
    let vendorID: String
    let productID: String
    let isLaser107a: Bool
    let count: Int
}

enum USBDeduper {
    /// Groups identical USB devices (same name, vendorID, productID) in stable
    /// first-seen order, carrying a count.
    static func group(_ devices: [USBDevice]) -> [USBGroup] {
        var order: [String] = []
        var groups: [String: USBGroup] = [:]
        for device in devices {
            let key = "\(device.name)|\(device.vendorID)|\(device.productID)"
            if let existing = groups[key] {
                groups[key] = USBGroup(id: existing.id, name: existing.name,
                                       vendorID: existing.vendorID, productID: existing.productID,
                                       isLaser107a: existing.isLaser107a, count: existing.count + 1)
            } else {
                order.append(key)
                groups[key] = USBGroup(id: key, name: device.name,
                                       vendorID: device.vendorID, productID: device.productID,
                                       isLaser107a: device.isLaser107a, count: 1)
            }
        }
        return order.compactMap { groups[$0] }
    }
}
