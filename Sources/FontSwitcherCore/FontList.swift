import Foundation

/// CSS-style comma-separated font lists (VS Code `editor.fontFamily`).
/// Only the primary (first) entry is ever replaced; fallbacks are kept verbatim.
public enum FontList {
    /// Replaces the first entry of `list` with `family`, keeping every fallback entry.
    public static func replacingPrimary(in list: String, with family: String) -> String {
        let formatted = format(family)
        guard let end = firstEntryEnd(list) else { return formatted }
        return formatted + list[end...]
    }

    /// The first entry with surrounding whitespace and quotes removed.
    public static func primary(of list: String) -> String? {
        let end = firstEntryEnd(list) ?? list.endIndex
        let entry = unquote(list[..<end].trimmingCharacters(in: .whitespaces))
        return entry.isEmpty ? nil : entry
    }

    /// Index of the comma ending the first entry (quote-aware), or nil when there is only one entry.
    static func firstEntryEnd(_ list: String) -> String.Index? {
        var quote: Character?
        var i = list.startIndex
        while i < list.endIndex {
            let c = list[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "'" || c == "\"" {
                quote = c
            } else if c == "," {
                return i
            }
            i = list.index(after: i)
        }
        // An unclosed quote (e.g. "Foo's Mono, Sarasa") must not swallow the fallbacks.
        return quote == nil ? nil : list.firstIndex(of: ",")
    }

    static func unquote(_ s: String) -> String {
        if s.count >= 2, let f = s.first, f == s.last, f == "'" || f == "\"" {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    static func format(_ family: String) -> String {
        if family.contains("'") { return "\"\(family)\"" }
        if family.contains(",") || family.contains("\"") { return "'\(family)'" }
        return family
    }
}
