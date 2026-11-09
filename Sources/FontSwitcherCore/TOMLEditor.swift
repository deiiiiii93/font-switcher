import Foundation

public enum TOMLScalar: Equatable, Sendable {
    case string(String)
    case float(Double)
    case number(Double)
}

public enum TOMLError: Error, Equatable, Sendable {
    case malformed(line: Int, reason: String)
}

/// Surgical, line-based editor for a single scalar key inside a TOML table (Warp `settings.toml`).
/// Only the value token is replaced; trailing comments and every other line are preserved.
/// Multi-line arrays/inline tables and multi-line strings are skipped so keys inside them never match.
public enum TOMLEditor {
    struct Entry {
        let line: Int
        let valueRange: Range<String.Index>  // within the line (sans "\r")
        let rawValue: String
    }

    struct Table {
        var headerLine: Int?
        var lastContentLine: Int?
        var entries: [String: Entry] = [:]
        var unsupported: Set<String> = []
    }

    public static func set(_ key: String, to value: TOMLScalar, inTable table: String, in text: String) throws -> String {
        var lines = text.components(separatedBy: "\n")
        let t = try scan(lines, table: table)
        if t.unsupported.contains(key) {
            throw TOMLError.malformed(line: 0, reason: "\(key) has a multi-line value FontSwitcher won't rewrite")
        }
        let encoded = encode(value)
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let cr = newline == "\r\n" ? "\r" : ""

        if let e = t.entries[key] {
            var line = lines[e.line]
            let hasCR = line.hasSuffix("\r")
            if hasCR { line.removeLast() }
            line.replaceSubrange(e.valueRange, with: encoded)
            lines[e.line] = line + (hasCR ? "\r" : "")
            return lines.joined(separator: "\n")
        }

        let newLine = "\(key) = \(encoded)"
        if let anchor = t.lastContentLine ?? t.headerLine {
            lines.insert(newLine + cr, at: anchor + 1)
            return lines.joined(separator: "\n")
        }
        // Table missing: append it.
        var out = text
        if !out.isEmpty {
            if out.utf8.last != UInt8(ascii: "\n") { out += newline }
            out += newline
        }
        return out + "[\(table)]" + newline + newLine + newline
    }

    /// Raw value: the unescaped string contents, or the literal number text.
    public static func value(_ key: String, inTable table: String, in text: String) -> String? {
        guard let t = try? scan(text.components(separatedBy: "\n"), table: table), let e = t.entries[key] else { return nil }
        if e.rawValue.hasPrefix("\"") { return unescapeBasic(String(e.rawValue.dropFirst().dropLast())) }
        if e.rawValue.hasPrefix("'") { return String(e.rawValue.dropFirst().dropLast()) }
        return e.rawValue
    }

    public static func formatFloat(_ d: Double) -> String {
        if d.rounded() == d, abs(d) < 1e15 { return String(Int64(d)) + ".0" }
        return "\(d)"
    }

    static func encode(_ v: TOMLScalar) -> String {
        switch v {
        case .float(let d): return formatFloat(d)
        case .number(let d): return JSONCEditor.formatNumber(d)
        case .string(let s):
            var out = "\""
            for ch in s.unicodeScalars {
                switch ch {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\t": out += "\\t"
                case "\r": out += "\\r"
                case _ where ch.value < 0x20: out += String(format: "\\u%04X", ch.value)
                default: out.unicodeScalars.append(ch)
                }
            }
            return out + "\""
        }
    }

    static func unescapeBasic(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let e = it.next() else { out.append(c); continue }
            switch e {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            default: out.append(e)
            }
        }
        return out
    }

    // MARK: Scanning

    /// Continuation state between lines: open bracket depth and an open multi-line string delimiter.
    struct Carry {
        var depth = 0
        var multiline: String?
        var isOpen: Bool { depth > 0 || multiline != nil }
    }

    static func scan(_ lines: [String], table: String) throws -> Table {
        var result = Table()
        var current = ""
        var inTarget = table.isEmpty
        var carry = Carry()

        for (n, raw) in lines.enumerated() {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if carry.isOpen {
                carry = try advance(line[...], carry: carry, line: n)
                if inTarget, !carry.isOpen { result.lastContentLine = n }
                continue
            }
            let body = line.drop(while: { $0 == " " || $0 == "\t" })
            if body.isEmpty || body.hasPrefix("#") { continue }
            if body.hasPrefix("[") {
                if body.hasPrefix("[[") {
                    current = "[[array]]"
                } else if let close = body.firstIndex(of: "]") {
                    current = body[body.index(after: body.startIndex)..<close].trimmingCharacters(in: .whitespaces)
                } else {
                    throw TOMLError.malformed(line: n, reason: "bad table header")
                }
                inTarget = current == table
                if inTarget { result.headerLine = n }
                continue
            }
            guard let eq = body.firstIndex(of: "=") else { continue }
            var k = body[..<eq].trimmingCharacters(in: .whitespaces)
            if k.count >= 2, k.hasPrefix("\""), k.hasSuffix("\"") { k = String(k.dropFirst().dropLast()) }
            let afterEq = body[body.index(after: eq)...]
            guard let vStart = afterEq.firstIndex(where: { $0 != " " && $0 != "\t" }) else { continue }
            let valueText = body[vStart...]
            carry = try advance(valueText, carry: Carry(), line: n)
            if inTarget {
                result.lastContentLine = carry.isOpen ? nil : n
                if carry.isOpen || valueText.hasPrefix("\"\"\"") || valueText.hasPrefix("'''") {
                    // Multi-line or triple-quoted values are not edited; refuse rather than corrupt or duplicate.
                    result.unsupported.insert(k)
                    result.entries[k] = nil
                } else {  // single-line scalar; a later duplicate wins
                    let end = scalarEnd(valueText)
                    let range = vStart..<end
                    result.entries[k] = Entry(line: n, valueRange: range, rawValue: String(line[range]))
                }
            }
        }
        if carry.isOpen { throw TOMLError.malformed(line: lines.count, reason: "unterminated value") }
        return result
    }

    /// End index of a single-line scalar value token (string or bare value), excluding trailing comments/space.
    static func scalarEnd(_ v: Substring) -> String.Index {
        if let q = v.first, q == "\"" || q == "'" {
            var i = v.index(after: v.startIndex)
            while i < v.endIndex {
                if v[i] == "\\", q == "\"" { i = v.index(i, offsetBy: 2, limitedBy: v.endIndex) ?? v.endIndex; continue }
                if v[i] == q { return v.index(after: i) }
                i = v.index(after: i)
            }
            return v.endIndex
        }
        let end = v.firstIndex(where: { $0 == "#" }) ?? v.endIndex
        var e = end
        while e > v.startIndex, v[v.index(before: e)] == " " || v[v.index(before: e)] == "\t" { e = v.index(before: e) }
        return e
    }

    /// Walks a fragment of value text, tracking strings and bracket depth across lines.
    static func advance(_ text: Substring, carry: Carry, line: Int) throws -> Carry {
        var c = carry
        var i = text.startIndex
        while i < text.endIndex {
            if let delim = c.multiline {
                if text[i...].hasPrefix(delim) {
                    c.multiline = nil
                    i = text.index(i, offsetBy: 3)
                } else {
                    if delim == "\"\"\"", text[i] == "\\" { i = text.index(i, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex; continue }
                    i = text.index(after: i)
                }
                continue
            }
            let ch = text[i]
            if text[i...].hasPrefix("\"\"\"") || text[i...].hasPrefix("'''") {
                c.multiline = String(text[i..<text.index(i, offsetBy: 3)])
                i = text.index(i, offsetBy: 3)
                continue
            }
            switch ch {
            case "#": return c
            case "[", "{": c.depth += 1
            case "]", "}": c.depth -= 1
            case "\"", "'":
                var j = text.index(after: i)
                var closed = false
                while j < text.endIndex {
                    if ch == "\"", text[j] == "\\" { j = text.index(j, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex; continue }
                    if text[j] == ch { closed = true; break }
                    j = text.index(after: j)
                }
                guard closed else { throw TOMLError.malformed(line: line, reason: "unterminated string") }
                i = j
            default: break
            }
            i = text.index(after: i)
        }
        return c
    }
}
