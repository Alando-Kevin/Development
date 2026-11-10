import Foundation

/// What a provider text message says, as far as NetPulse can tell.
enum ParsedMessage: Equatable {
    case purchase(sizeBytes: Int64, cost: Double?, expires: Date?)
    case balance(remainingBytes: Int64)
    case unrecognised
}

/// Pulls bundle purchases and data balances out of a provider SMS.
/// Message wording varies, so this looks for amounts and key words rather than one exact format.
enum MessageParser {
    private static let purchaseWords = ["bought", "purchased", "purchase of", "successfully", "you have received", "activated"]
    private static let balanceWords = ["balance", "remaining", "bal:", "bal "]

    static func parse(_ text: String, now: Date = Date()) -> ParsedMessage {
        let lower = text.lowercased()
        let amounts = dataAmounts(in: lower)
        guard let first = amounts.first else { return .unrecognised }

        // Purchase confirmations often also quote a new balance, so check for a purchase first.
        if purchaseWords.contains(where: { lower.contains($0) }) {
            return .purchase(sizeBytes: first, cost: cost(in: lower), expires: expiry(in: lower, now: now))
        }
        if balanceWords.contains(where: { lower.contains($0) }) {
            // A balance message can list several bundles; add them up.
            return .balance(remainingBytes: amounts.reduce(0, +))
        }
        return .unrecognised
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ""))
    }

    /// Every data amount in the text, in bytes, in the order it appears.
    static func dataAmounts(in text: String) -> [Int64] {
        matches(#"(\d[\d,]*(?:\.\d+)?)\s*(gb|mb|kb)\b"#, in: text).compactMap { groups in
            guard let value = number(groups[1]) else { return nil }
            let multiplier: Double
            switch groups[2].lowercased() {
            case "gb": multiplier = 1_000_000_000
            case "mb": multiplier = 1_000_000
            default: multiplier = 1_000
            }
            return Int64(value * multiplier)
        }
    }

    private static func cost(in text: String) -> Double? {
        matches(#"(?:kshs?|kes)\.?\s*(\d[\d,]*(?:\.\d+)?)"#, in: text).first.flatMap { number($0[1]) }
    }

    private static func expiry(in text: String, now: Date) -> Date? {
        let calendar = Calendar.current

        // "valid for 24 hours", "7 days", "1 hr"
        if let groups = matches(#"(\d+)\s*(hours?|hrs?|days?|weeks?)\b"#, in: text).first, let count = Int(groups[1]) {
            let unit = groups[2].lowercased()
            let component: Calendar.Component = unit.hasPrefix("h") ? .hour : unit.hasPrefix("d") ? .day : .weekOfYear
            return calendar.date(byAdding: component, value: count, to: now)
        }

        // "12/11/2026" or "12-11-2026" (day first), or "2026-11-12"
        var parts = DateComponents()
        if let groups = matches(#"(\d{4})-(\d{1,2})-(\d{1,2})"#, in: text).first {
            parts.year = Int(groups[1]); parts.month = Int(groups[2]); parts.day = Int(groups[3])
        } else if let groups = matches(#"(\d{1,2})[/-](\d{1,2})[/-](\d{4})"#, in: text).first {
            parts.day = Int(groups[1]); parts.month = Int(groups[2]); parts.year = Int(groups[3])
        } else {
            return nil
        }
        parts.hour = 23
        parts.minute = 59
        return calendar.date(from: parts)
    }
}
