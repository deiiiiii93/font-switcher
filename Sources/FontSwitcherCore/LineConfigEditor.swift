import Foundation

/// `key = value` (Ghostty) or `key value` (kitty) line-oriented config files.
public enum LineStyle: Sendable {
    case ghostty
    case kitty
}

/// Which occurrence of a repeated key to edit/read.
/// Ghostty `font-family` is a list whose first line is the primary font (`.first`);
/// single-valued keys take their last occurrence (`.last`).
public enum Occurrence: Sendable {
    case first
    case last
}

public enum LineConfigEditor {
    struct Hit {
        let line: Int
        let prefix: Substring  // indentation + key + separator, preserved verbatim
        let value: String
        let cr: Bool
    }

    /// Sets `key` to `value` (raw text, already formatted for the file). Replaces the chosen
    /// occurrence in place or appends a new line, inserting a separating newline when the
    /// file does not end in one.
    public static func set(_ key: String, to rawValue: String, in text: String, style: LineStyle, occurrence: Occurrence) -> String {
        // Defense in depth: a value must never start a new config line, whatever the caller validated.
        let value = rawValue.filter { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
        var lines = text.components(separatedBy: "\n")
        if let hit = find(key, in: lines, style: style, occurrence: occurrence) {
            lines[hit.line] = hit.prefix + value + (hit.cr ? "\r" : "")
            return lines.joined(separator: "\n")
        }
        let separator = style == .ghostty ? " = " : " "
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let line = key + separator + value + newline
        if text.isEmpty { return line }
        // Byte check: Swift treats "\r\n" as one Character, so hasSuffix("\n") misses CRLF endings.
        return text + (text.utf8.last == UInt8(ascii: "\n") ? "" : newline) + line
    }

    /// The raw value of `key` at the chosen occurrence, or nil when absent.
    public static func value(_ key: String, in text: String, style: LineStyle, occurrence: Occurrence) -> String? {
        find(key, in: text.components(separatedBy: "\n"), style: style, occurrence: occurrence)?.value
    }

    static func find(_ key: String, in lines: [String], style: LineStyle, occurrence: Occurrence) -> Hit? {
        var result: Hit?
        for (n, rawLine) in lines.enumerated() {
            let cr = rawLine.hasSuffix("\r")
            let line = cr ? Substring(rawLine.dropLast()) : Substring(rawLine)
            guard let hit = match(key, line: line, style: style) else { continue }
            result = Hit(line: n, prefix: hit.prefix, value: hit.value, cr: cr)
            if occurrence == .first { break }
        }
        return result
    }

    static func match(_ key: String, line: Substring, style: LineStyle) -> (prefix: Substring, value: String)? {
        let body = line.drop(while: { $0 == " " || $0 == "\t" })
        if body.hasPrefix("#") || body.isEmpty { return nil }
        switch style {
        case .ghostty:
            guard let eq = body.firstIndex(of: "=") else { return nil }
            guard body[..<eq].trimmingCharacters(in: .whitespaces) == key else { return nil }
            let afterEq = body.index(after: eq)
            let valueStart = body[afterEq...].firstIndex(where: { $0 != " " && $0 != "\t" }) ?? body.endIndex
            return (line[..<valueStart], body[valueStart...].trimmingCharacters(in: .whitespaces))
        case .kitty:
            guard let ws = body.firstIndex(where: { $0 == " " || $0 == "\t" }), body[..<ws] == key else { return nil }
            let valueStart = body[ws...].firstIndex(where: { $0 != " " && $0 != "\t" }) ?? body.endIndex
            return (line[..<valueStart], body[valueStart...].trimmingCharacters(in: .whitespaces))
        }
    }
}

/// Value formatting rules for line configs (spec A3).
public enum LineValue {
    /// Ghostty values may be wrapped in one pair of double quotes.
    public static func ghosttyFamily(from raw: String) -> String {
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") { return String(raw.dropFirst().dropLast()) }
        return raw
    }

    /// kitty: keep the font-spec form (`family="…"`) if the existing value uses it, else plain.
    public static func kittyFamily(_ family: String, existingRaw: String?) -> String {
        // A quote would end the spec's quoted value early, so such names use the plain form.
        if let existingRaw, existingRaw.contains("family="), !family.contains("\"") { return "family=\"\(family)\"" }
        return family
    }

    /// Extracts the family name from either kitty form.
    public static func kittyFamilyName(from raw: String) -> String {
        guard let r = raw.range(of: "family=") else { return raw }
        let rest = raw[r.upperBound...]
        if rest.hasPrefix("\"") || rest.hasPrefix("'") {
            let q = rest.first!
            let inner = rest.dropFirst()
            return String(inner.prefix(while: { $0 != q }))
        }
        return String(rest.prefix(while: { $0 != " " && $0 != "\t" }))
    }
}
