import Foundation
import Testing
@testable import FontSwitcherCore

@Suite struct GhosttyEditorTests {
    // Real-shaped: comments, a fallback font-family line, and no final newline.
    let config = "# theme\ntheme = dark\n# font-family = Old\nfont-family = Berkeley Mono\nfont-family = Sarasa Mono SC"

    @Test func replacesFirstFontFamilyKeepingFallbacks() {
        let out = LineConfigEditor.set("font-family", to: "Zed Mono", in: config, style: .ghostty, occurrence: .first)
        #expect(out == "# theme\ntheme = dark\n# font-family = Old\nfont-family = Zed Mono\nfont-family = Sarasa Mono SC")
    }

    @Test func appendsMissingKeyAfterSeparatingNewline() {
        let out = LineConfigEditor.set("font-size", to: "14", in: config, style: .ghostty, occurrence: .last)
        #expect(out == config + "\nfont-size = 14\n")
    }

    @Test func appendsToFileEndingInNewline() {
        #expect(LineConfigEditor.set("a", to: "1", in: "x = 2\n", style: .ghostty, occurrence: .last) == "x = 2\na = 1\n")
        #expect(LineConfigEditor.set("a", to: "1", in: "", style: .ghostty, occurrence: .last) == "a = 1\n")
    }

    @Test func lastOccurrenceForSingleValuedKeys() {
        let src = "font-size = 12\nfont-size=13\n"
        #expect(LineConfigEditor.set("font-size", to: "15", in: src, style: .ghostty, occurrence: .last) == "font-size = 12\nfont-size=15\n")
        #expect(LineConfigEditor.value("font-size", in: src, style: .ghostty, occurrence: .last) == "13")
    }

    @Test func readsAndStripsQuotes() {
        #expect(LineConfigEditor.value("font-family", in: config, style: .ghostty, occurrence: .first) == "Berkeley Mono")
        #expect(LineValue.ghosttyFamily(from: "\"JetBrains Mono\"") == "JetBrains Mono")
    }

    @Test func doesNotMatchKeyPrefixes() {
        let src = "font-family-bold = X\n"
        #expect(LineConfigEditor.value("font-family", in: src, style: .ghostty, occurrence: .first) == nil)
    }

    @Test func preservesIndentationAndCRLF() {
        let src = "  font-size = 12\r\nx = 1\r\n"
        #expect(LineConfigEditor.set("font-size", to: "14", in: src, style: .ghostty, occurrence: .last) == "  font-size = 14\r\nx = 1\r\n")
    }
}

@Suite struct KittyEditorTests {
    let config = "#: Fonts\n# font_family      Berkeley Mono\n# BEGIN_KITTY_FONTS\nfont_family      family=\"Zed Mono\"\nbold_font        auto\n# END_KITTY_FONTS"

    @Test func replacesSpecFormKeepingSpacing() {
        let raw = LineConfigEditor.value("font_family", in: config, style: .kitty, occurrence: .last)
        #expect(raw == "family=\"Zed Mono\"")
        let value = LineValue.kittyFamily("Berkeley Mono", existingRaw: raw)
        let out = LineConfigEditor.set("font_family", to: value, in: config, style: .kitty, occurrence: .last)
        #expect(out == config.replacingOccurrences(of: "font_family      family=\"Zed Mono\"", with: "font_family      family=\"Berkeley Mono\""))
        #expect(out.contains("# font_family      Berkeley Mono"))
    }

    @Test func plainFormStaysPlain() {
        #expect(LineValue.kittyFamily("Berkeley Mono", existingRaw: "Menlo") == "Berkeley Mono")
        #expect(LineValue.kittyFamily("Berkeley Mono", existingRaw: nil) == "Berkeley Mono")
        #expect(LineValue.kittyFamily("Berkeley Mono", existingRaw: "family=\"Zed Mono\" style=Bold features=+zero") == "family=\"Berkeley Mono\"")
    }

    @Test func parsesBothForms() {
        #expect(LineValue.kittyFamilyName(from: "family=\"Zed Mono\" style=Regular") == "Zed Mono")
        #expect(LineValue.kittyFamilyName(from: "family=Menlo") == "Menlo")
        #expect(LineValue.kittyFamilyName(from: "Berkeley Mono") == "Berkeley Mono")
    }

    @Test func lastOccurrenceWinsAndAppendWithoutFinalNewline() {
        let src = "font_size 12\nfont_size 13"
        #expect(LineConfigEditor.set("font_size", to: "14", in: src, style: .kitty, occurrence: .last) == "font_size 12\nfont_size 14")
        #expect(LineConfigEditor.set("font_size", to: "14", in: config, style: .kitty, occurrence: .last) == config + "\nfont_size 14\n")
    }

    @Test func keyNeedsWhitespaceSeparator() {
        #expect(LineConfigEditor.value("font", in: "font_size 12\n", style: .kitty, occurrence: .last) == nil)
    }
}

@Suite struct TOMLEditorTests {
    let warp = """
    [appearance]
    theme = "x"

    [appearance.text]
    notebook_font_size = 14.0
    ai_font_name = "Sono"
    font_name = "Berkeley Mono Variable" # primary
    font_size = 14.0

    [privacy]
    rules = [
      { name = "a", font_name = "nope" },
      { name = "b" },
    ]
    note = \"\"\"
    font_size = 99
    \"\"\"
    """

    @Test func replacesOnlyTargetTableKeys() throws {
        var out = try TOMLEditor.set("font_name", to: .string("Zed Mono"), inTable: "appearance.text", in: warp)
        out = try TOMLEditor.set("font_size", to: .float(16), inTable: "appearance.text", in: out)
        let expected = warp
            .replacingOccurrences(of: "font_name = \"Berkeley Mono Variable\" # primary", with: "font_name = \"Zed Mono\" # primary")
            .replacingOccurrences(of: "font_size = 14.0\n\n", with: "font_size = 16.0\n\n")
        #expect(out == expected)
    }

    @Test func readsValues() {
        #expect(TOMLEditor.value("font_name", inTable: "appearance.text", in: warp) == "Berkeley Mono Variable")
        #expect(TOMLEditor.value("font_size", inTable: "appearance.text", in: warp) == "14.0")
        #expect(TOMLEditor.value("font_size", inTable: "privacy", in: warp) == nil)
    }

    @Test func insertsAfterLastKeyOfTable() throws {
        let src = "[appearance.text]\nfont_size = 14.0\n\n[other]\nk = 1\n"
        let out = try TOMLEditor.set("font_name", to: .string("X"), inTable: "appearance.text", in: src)
        #expect(out == "[appearance.text]\nfont_size = 14.0\nfont_name = \"X\"\n\n[other]\nk = 1\n")
    }

    @Test func appendsMissingTable() throws {
        #expect(try TOMLEditor.set("font_size", to: .float(13.5), inTable: "appearance.text", in: "[a]\nb = 1")
            == "[a]\nb = 1\n\n[appearance.text]\nfont_size = 13.5\n")
        #expect(try TOMLEditor.set("font_size", to: .float(13), inTable: "appearance.text", in: "")
            == "[appearance.text]\nfont_size = 13.0\n")
    }

    @Test func escapesStrings() throws {
        let out = try TOMLEditor.set("font_name", to: .string("A \"B\""), inTable: "t", in: "[t]\n")
        #expect(out == "[t]\nfont_name = \"A \\\"B\\\"\"\n")
    }

    @Test func unterminatedMultilineThrows() {
        #expect(throws: TOMLError.self) { try TOMLEditor.set("a", to: .float(1), inTable: "t", in: "[t]\nx = [\n1,\n") }
    }
}

@Suite struct NumberFormatTests {
    @Test func formats() {
        #expect(JSONCEditor.formatNumber(14) == "14")
        #expect(JSONCEditor.formatNumber(13.5) == "13.5")
        #expect(TOMLEditor.formatFloat(14) == "14.0")
        #expect(TOMLEditor.formatFloat(13.5) == "13.5")
    }
}
