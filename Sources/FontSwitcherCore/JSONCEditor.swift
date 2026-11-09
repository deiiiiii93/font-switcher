import Foundation

/// A scalar value the editors can write.
public enum JSONScalar: Equatable, Sendable {
    case string(String)
    case number(Double)
}

public enum JSONCError: Error, Equatable, Sendable {
    case malformed(offset: Int, reason: String)
}

/// Surgical editor for JSON-with-comments files (VS Code / Cursor / Herdr settings).
///
/// The file is never re-serialized: it is scanned once to locate the byte range of a
/// top-level member's value, and only that range is replaced. Everything else
/// (comments, ordering, whitespace, trailing commas) is preserved byte for byte.
public enum JSONCEditor {
    /// Sets a top-level `key` to `value`, replacing the last occurrence or inserting a new member.
    public static func setTopLevel(_ key: String, to value: JSONScalar, in text: String) throws -> String {
        let bytes = Array(text.utf8)
        let doc = try parse(bytes)
        let encoded = Array(encode(value).utf8)

        if let member = doc.members.last(where: { $0.key == key }) {
            var out = bytes
            out.replaceSubrange(member.valueStart..<member.valueEnd, with: encoded)
            return String(decoding: out, as: UTF8.self)
        }

        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let memberText = "\(encodeString(key)): \(encode(value))"
        var out = bytes
        if let last = doc.members.last {
            let indent = indentation(before: last.keyStart, in: bytes)
            let insertion = Array(",\(newline)\(indent)\(memberText)".utf8)
            out.insert(contentsOf: insertion, at: last.valueEnd)
        } else {
            let inner = bytes[(doc.openBrace + 1)..<doc.closeBrace]
            let hasNewline = inner.contains(UInt8(ascii: "\n"))
            let insertion = Array("\(newline)  \(memberText)\(hasNewline ? "" : newline)".utf8)
            out.insert(contentsOf: insertion, at: doc.openBrace + 1)
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The decoded string value of a top-level key, or nil if absent or not a string.
    public static func topLevelString(_ key: String, in text: String) throws -> String? {
        let bytes = Array(text.utf8)
        let doc = try parse(bytes)
        guard let m = doc.members.last(where: { $0.key == key }), bytes[m.valueStart] == UInt8(ascii: "\"") else {
            return nil
        }
        var s = JSONCScanner(bytes)
        s.i = m.valueStart
        return try s.scanString()
    }

    /// The numeric value of a top-level key, or nil if absent or not a number.
    public static func topLevelNumber(_ key: String, in text: String) throws -> Double? {
        let bytes = Array(text.utf8)
        let doc = try parse(bytes)
        guard let m = doc.members.last(where: { $0.key == key }) else { return nil }
        return Double(String(decoding: bytes[m.valueStart..<m.valueEnd], as: UTF8.self))
    }

    static func parse(_ bytes: [UInt8]) throws -> JSONCDocument {
        var s = JSONCScanner(bytes)
        return try s.scanDocument()
    }

    // MARK: Encoding

    static func encode(_ value: JSONScalar) -> String {
        switch value {
        case .string(let s): return encodeString(s)
        case .number(let d): return formatNumber(d)
        }
    }

    /// `14` for integral values, shortest round-trip form otherwise (`13.5`).
    public static func formatNumber(_ d: Double) -> String {
        if d.rounded() == d, abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }

    static func encodeString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    static func indentation(before index: Int, in bytes: [UInt8]) -> String {
        var j = index
        while j > 0, bytes[j - 1] == UInt8(ascii: " ") || bytes[j - 1] == UInt8(ascii: "\t") { j -= 1 }
        // Only treat it as indentation when the key starts its own line.
        if j == 0 || bytes[j - 1] == UInt8(ascii: "\n") {
            return String(decoding: bytes[j..<index], as: UTF8.self)
        }
        return "  "
    }
}

// MARK: - Scanner

struct JSONCDocument {
    struct Member {
        let key: String
        let keyStart: Int
        let valueStart: Int
        let valueEnd: Int
    }
    var openBrace: Int
    var closeBrace: Int
    var members: [Member]
}

struct JSONCScanner {
    let b: [UInt8]
    var i = 0

    init(_ bytes: [UInt8]) { b = bytes }

    func fail(_ reason: String) -> JSONCError { .malformed(offset: i, reason: reason) }

    var atEnd: Bool { i >= b.count }
    var cur: UInt8 { b[i] }

    mutating func scanDocument() throws -> JSONCDocument {
        try skipTrivia()
        guard !atEnd, cur == UInt8(ascii: "{") else { throw fail("expected '{'") }
        let open = i
        i += 1
        var members: [JSONCDocument.Member] = []
        while true {
            try skipTrivia()
            guard !atEnd else { throw fail("unterminated object") }
            if cur == UInt8(ascii: "}") { break }
            guard cur == UInt8(ascii: "\"") else { throw fail("expected key") }
            let keyStart = i
            let key = try scanString()
            try skipTrivia()
            guard !atEnd, cur == UInt8(ascii: ":") else { throw fail("expected ':'") }
            i += 1
            try skipTrivia()
            let valueStart = i
            try skipValue()
            members.append(.init(key: key, keyStart: keyStart, valueStart: valueStart, valueEnd: i))
            try skipTrivia()
            guard !atEnd else { throw fail("unterminated object") }
            if cur == UInt8(ascii: ",") { i += 1; continue }
            if cur == UInt8(ascii: "}") { break }
            throw fail("expected ',' or '}'")
        }
        let close = i
        i += 1
        try skipTrivia()
        guard atEnd else { throw fail("trailing content") }
        return JSONCDocument(openBrace: open, closeBrace: close, members: members)
    }

    mutating func skipTrivia() throws {
        while !atEnd {
            switch cur {
            case 0x20, 0x09, 0x0A, 0x0D: i += 1
            case UInt8(ascii: "/"):
                guard i + 1 < b.count else { throw fail("stray '/'") }
                if b[i + 1] == UInt8(ascii: "/") {
                    while !atEnd, cur != 0x0A { i += 1 }
                } else if b[i + 1] == UInt8(ascii: "*") {
                    i += 2
                    while true {
                        guard i + 1 < b.count else { throw fail("unterminated comment") }
                        if b[i] == UInt8(ascii: "*"), b[i + 1] == UInt8(ascii: "/") { i += 2; break }
                        i += 1
                    }
                } else {
                    throw fail("stray '/'")
                }
            default: return
            }
        }
    }

    mutating func skipValue() throws {
        guard !atEnd else { throw fail("expected value") }
        switch cur {
        case UInt8(ascii: "\""): _ = try scanString()
        case UInt8(ascii: "{"), UInt8(ascii: "["): try skipContainer()
        default:
            let start = i
            while !atEnd, isScalarByte(cur) { i += 1 }
            guard i > start else { throw fail("expected value") }
        }
    }

    func isScalarByte(_ c: UInt8) -> Bool {
        (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z")) || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
            || (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9"))
            || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".")
    }

    /// Skips a nested object/array, tracking strings and comments so brackets inside them don't count.
    mutating func skipContainer() throws {
        var stack: [UInt8] = []
        repeat {
            guard !atEnd else { throw fail("unterminated container") }
            let c = cur
            switch c {
            case UInt8(ascii: "{"): stack.append(UInt8(ascii: "}")); i += 1
            case UInt8(ascii: "["): stack.append(UInt8(ascii: "]")); i += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                guard stack.last == c else { throw fail("mismatched bracket") }
                stack.removeLast(); i += 1
            case UInt8(ascii: "\""): _ = try scanString()
            case UInt8(ascii: "/"): try skipTrivia()
            default: i += 1
            }
        } while !stack.isEmpty
    }

    /// Scans a JSON string starting at the opening quote and returns its decoded value.
    mutating func scanString() throws -> String {
        guard !atEnd, cur == UInt8(ascii: "\"") else { throw fail("expected string") }
        i += 1
        var raw: [UInt8] = []
        var scalars = String.UnicodeScalarView()
        func flush() {
            scalars.append(contentsOf: String(decoding: raw, as: UTF8.self).unicodeScalars)
            raw.removeAll()
        }
        while true {
            guard !atEnd else { throw fail("unterminated string") }
            let c = cur
            if c == UInt8(ascii: "\"") { i += 1; break }
            if c == 0x0A { throw fail("newline in string") }
            if c != UInt8(ascii: "\\") { raw.append(c); i += 1; continue }
            flush()
            guard i + 1 < b.count else { throw fail("bad escape") }
            let e = b[i + 1]
            i += 2
            switch e {
            case UInt8(ascii: "\""): scalars.append("\"")
            case UInt8(ascii: "\\"): scalars.append("\\")
            case UInt8(ascii: "/"): scalars.append("/")
            case UInt8(ascii: "b"): scalars.append("\u{08}")
            case UInt8(ascii: "f"): scalars.append("\u{0C}")
            case UInt8(ascii: "n"): scalars.append("\n")
            case UInt8(ascii: "r"): scalars.append("\r")
            case UInt8(ascii: "t"): scalars.append("\t")
            case UInt8(ascii: "u"):
                let code = try hex4()
                if (0xD800...0xDBFF).contains(code), i + 1 < b.count,
                   b[i] == UInt8(ascii: "\\"), b[i + 1] == UInt8(ascii: "u") {
                    i += 2
                    let low = try hex4()
                    if (0xDC00...0xDFFF).contains(low) {
                        scalars.append(Unicode.Scalar(0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)) ?? "\u{FFFD}")
                    } else {
                        // Unpaired high surrogate: replace it and keep the following escape on its own.
                        scalars.append("\u{FFFD}")
                        scalars.append(Unicode.Scalar(low) ?? "\u{FFFD}")
                    }
                } else {
                    scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                }
            default: throw fail("bad escape")
            }
        }
        flush()
        return String(scalars)
    }

    mutating func hex4() throws -> UInt32 {
        guard i + 4 <= b.count, let v = UInt32(String(decoding: b[i..<(i + 4)], as: UTF8.self), radix: 16) else {
            throw fail("bad \\u escape")
        }
        i += 4
        return v
    }
}
