import Foundation
import Testing
@testable import FontSwitcherCore

@Suite struct JSONCEditorTests {
    let complex = """
    // VS Code settings
    {
        /* block
           comment */
        "workbench.colorTheme": "Dark", // trailing
        "editor.fontFamily": "Zed Mono, Sarasa Mono Slab CL",
        "nested": { "editor.fontFamily": "Inner", "arr": [1, "}", {"a": "/*"}] },
        "url": "http://x//y",
        "editor.fontSize": 14,
    }
    """

    @Test func replacesValueKeepingEveryOtherByte() throws {
        let out = try JSONCEditor.setTopLevel("editor.fontFamily", to: .string("Berkeley Mono"), in: complex)
        let expected = complex.replacingOccurrences(
            of: "\"editor.fontFamily\": \"Zed Mono, Sarasa Mono Slab CL\"",
            with: "\"editor.fontFamily\": \"Berkeley Mono\"")
        #expect(out == expected)
    }

    @Test func nestedSameNameKeyUntouched() throws {
        let out = try JSONCEditor.setTopLevel("editor.fontFamily", to: .string("X"), in: complex)
        #expect(out.contains("{ \"editor.fontFamily\": \"Inner\""))
        #expect(try JSONCEditor.topLevelString("editor.fontFamily", in: complex) == "Zed Mono, Sarasa Mono Slab CL")
    }

    @Test func replacesNumber() throws {
        let out = try JSONCEditor.setTopLevel("editor.fontSize", to: .number(13.5), in: complex)
        #expect(out.contains("\"editor.fontSize\": 13.5,"))
        #expect(try JSONCEditor.topLevelNumber("editor.fontSize", in: complex) == 14)
    }

    @Test func integralNumberHasNoDecimalPoint() throws {
        let out = try JSONCEditor.setTopLevel("editor.fontSize", to: .number(16), in: complex)
        #expect(out.contains("\"editor.fontSize\": 16,"))
    }

    @Test func insertsMissingKeyAfterLastMemberWithIndentation() throws {
        let src = "{\n    \"a\": 1,\n    \"b\": \"x\"\n}"
        let out = try JSONCEditor.setTopLevel("font", to: .string("Geist Mono"), in: src)
        #expect(out == "{\n    \"a\": 1,\n    \"b\": \"x\",\n    \"font\": \"Geist Mono\"\n}")
    }

    @Test func insertsMissingKeyWhenTrailingCommaPresent() throws {
        let src = "{\n  \"a\": 1,\n}\n"
        let out = try JSONCEditor.setTopLevel("b", to: .number(2), in: src)
        #expect(out == "{\n  \"a\": 1,\n  \"b\": 2,\n}\n")
        #expect(try JSONCEditor.topLevelNumber("b", in: out) == 2)
    }

    @Test func insertsIntoEmptyObject() throws {
        #expect(try JSONCEditor.setTopLevel("k", to: .string("v"), in: "{}") == "{\n  \"k\": \"v\"\n}")
        #expect(try JSONCEditor.setTopLevel("k", to: .string("v"), in: "{\n}\n") == "{\n  \"k\": \"v\"\n}\n")
    }

    @Test func escapesStrings() throws {
        let out = try JSONCEditor.setTopLevel("k", to: .string("a\"b\\c"), in: "{}")
        #expect(out.contains(#""k": "a\"b\\c""#))
        #expect(try JSONCEditor.topLevelString("k", in: out) == "a\"b\\c")
    }

    @Test func decodesEscapesWhenReading() throws {
        #expect(try JSONCEditor.topLevelString("k", in: #"{"k": "\"Fira Code\" é"}"#) == "\"Fira Code\" é")
    }

    @Test(arguments: ["", "{", "{\"a\" 1}", "{\"a\": 1} x", "[1]", "{\"a\": \"unterminated}", "{\"a\": 1 /* open"])
    func malformedThrows(_ src: String) {
        #expect(throws: JSONCError.self) { try JSONCEditor.setTopLevel("a", to: .number(1), in: src) }
    }

    @Test func lastDuplicateKeyIsEdited() throws {
        let out = try JSONCEditor.setTopLevel("a", to: .number(3), in: "{\"a\": 1, \"a\": 2}")
        #expect(out == "{\"a\": 1, \"a\": 3}")
    }

    @Test func crlfFilesInsertWithCRLF() throws {
        let out = try JSONCEditor.setTopLevel("b", to: .number(2), in: "{\r\n  \"a\": 1\r\n}")
        #expect(out == "{\r\n  \"a\": 1,\r\n  \"b\": 2\r\n}")
    }
}

@Suite struct FontListTests {
    @Test func replacesPrimaryKeepingFallbacks() {
        #expect(FontList.replacingPrimary(in: "Zed Mono, Sarasa Mono Slab CL", with: "Berkeley Mono") == "Berkeley Mono, Sarasa Mono Slab CL")
        #expect(FontList.replacingPrimary(in: "monospace", with: "Berkeley Mono") == "Berkeley Mono")
        #expect(FontList.replacingPrimary(in: "", with: "Berkeley Mono") == "Berkeley Mono")
    }

    @Test func quotedFirstEntry() {
        #expect(FontList.replacingPrimary(in: "'Fira Code', Menlo", with: "Berkeley Mono") == "Berkeley Mono, Menlo")
        #expect(FontList.replacingPrimary(in: "\"Fira Code\"", with: "Berkeley Mono") == "Berkeley Mono")
        #expect(FontList.replacingPrimary(in: "'A, B', Menlo", with: "X") == "X, Menlo")
    }

    @Test func familyNeedingQuotesIsQuoted() {
        #expect(FontList.replacingPrimary(in: "Menlo", with: "Odd, Font") == "'Odd, Font'")
        #expect(FontList.replacingPrimary(in: "Menlo", with: "O'Brien") == "\"O'Brien\"")
    }

    @Test func primaryStripsQuotes() {
        #expect(FontList.primary(of: "'Fira Code', Menlo") == "Fira Code")
        #expect(FontList.primary(of: " Zed Mono , X") == "Zed Mono")
        #expect(FontList.primary(of: "") == nil)
    }
}
