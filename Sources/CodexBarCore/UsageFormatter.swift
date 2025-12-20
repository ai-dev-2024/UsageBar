import Foundation

public enum UsageFormatter {
    public static func usageLine(remaining: Double, used: Double) -> String {
        String(format: "%.0f%% left", remaining)
    }

    public static func resetCountdownDescription(from date: Date, now: Date = .init()) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 1 { return "now" }

        let totalMinutes = max(1, Int(ceil(seconds / 60.0)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 { return "in \(days)d \(hours)h" }
            return "in \(days)d"
        }
        if hours > 0 {
            if minutes > 0 { return "in \(hours)h \(minutes)m" }
            return "in \(hours)h"
        }
        return "in \(totalMinutes)m"
    }

    public static func resetDescription(from date: Date, now: Date = .init()) -> String {
        // Human-friendly phrasing: today / tomorrow / date+time.
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return "tomorrow, \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    public static func updatedString(from date: Date, now: Date = .init()) -> String {
        let delta = now.timeIntervalSince(date)
        if abs(delta) < 60 {
            return "Updated just now"
        }
        if let hours = Calendar.current.dateComponents([.hour], from: date, to: now).hour, hours < 24 {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .abbreviated
            return "Updated \(rel.localizedString(for: date, relativeTo: now))"
        } else {
            return "Updated \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    public static func creditsString(from value: Double) -> String {
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.maximumFractionDigits = 2
        let formatted = number.string(from: NSNumber(value: value)) ?? String(Int(value))
        return "\(formatted) left"
    }

    public static func usdString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    public static func tokenCountString(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""

        let units: [(threshold: Int, divisor: Double, suffix: String)] = [
            (1_000_000_000, 1_000_000_000, "B"),
            (1_000_000, 1_000_000, "M"),
            (1000, 1000, "K"),
        ]

        for unit in units where absValue >= unit.threshold {
            let scaled = Double(absValue) / unit.divisor
            let formatted: String
            if scaled >= 10 {
                formatted = String(format: "%.0f", scaled)
            } else {
                var s = String(format: "%.1f", scaled)
                if s.hasSuffix(".0") { s.removeLast(2) }
                formatted = s
            }
            return "\(sign)\(formatted)\(unit.suffix)"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func creditEventSummary(_ event: CreditEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.maximumFractionDigits = 2
        let credits = number.string(from: NSNumber(value: event.creditsUsed)) ?? "0"
        return "\(formatter.string(from: event.date)) · \(event.service) · \(credits) credits"
    }

    public static func creditEventCompact(_ event: CreditEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.maximumFractionDigits = 2
        let credits = number.string(from: NSNumber(value: event.creditsUsed)) ?? "0"
        return "\(formatter.string(from: event.date)) — \(event.service): \(credits)"
    }

    public static func creditShort(_ value: Double) -> String {
        if value >= 1000 {
            let k = value / 1000
            return String(format: "%.1fk", k)
        }
        return String(format: "%.0f", value)
    }

    public static func truncatedSingleLine(_ text: String, max: Int = 80) -> String {
        let single = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard single.count > max else { return single }
        let idx = single.index(single.startIndex, offsetBy: max)
        return "\(single[..<idx])…"
    }

    /// Cleans a provider plan string: strip ANSI/bracket noise, drop boilerplate words, collapse whitespace, and
    /// ensure a leading capital if the result starts lowercase.
    public static func cleanPlanName(_ text: String) -> String {
        let stripped = TextParsing.stripANSICodes(text)
        let withoutCodes = stripped.replacingOccurrences(
            of: #"^\s*(?:\[\d{1,3}m\s*)+"#,
            with: "",
            options: [.regularExpression])
        let withoutBoilerplate = withoutCodes.replacingOccurrences(
            of: #"(?i)\b(claude|codex|account|plan)\b"#,
            with: "",
            options: [.regularExpression])
        var cleaned = withoutBoilerplate
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Capitalize first letter only if lowercase, preserving acronyms like "AI"
        if let first = cleaned.first, first.isLowercase {
            return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        return cleaned
    }
}
