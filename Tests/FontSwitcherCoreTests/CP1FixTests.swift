import Foundation
import Testing
@testable import FontSwitcherCore

/// Regression tests for checkpoint CP1 findings.
@Suite struct CP1FixTests {
    @Test func invalidSurrogatePairDoesNotCrash() throws {
        #expect(try JSONCEditor.topLevelString("k", in: #"{"k": "\uD83DA"}"#) == "\u{FFFD}A")
        #expect(try JSONCEditor.topLevelString("k", in: #"{"k": "😀"}"#) == "😀")
    }

    @Test func unclosedQuoteKeepsFallbacks() {
        #expect(FontList.replacingPrimary(in: "Foo's Mono, Sarasa", with: "X") == "X, Sarasa")
    }

    @Test func crlfAppendAddsNoBlankLine() throws {
        #expect(LineConfigEditor.set("b", to: "2", in: "a = 1\r\n", style: .ghostty, occurrence: .last) == "a = 1\r\nb = 2\r\n")
        #expect(try TOMLEditor.set("b", to: .float(2), inTable: "t", in: "[a]\r\nx = 1\r\n") == "[a]\r\nx = 1\r\n\r\n[t]\r\nb = 2.0\r\n")
    }

    @Test func tripleQuotedTargetValueThrowsInsteadOfCorrupting() {
        #expect(throws: TOMLError.self) { try TOMLEditor.set("font_name", to: .string("X"), inTable: "t", in: "[t]\nfont_name = '''Hack'''\n") }
        #expect(throws: TOMLError.self) { try TOMLEditor.set("font_name", to: .string("X"), inTable: "t", in: "[t]\nfont_name = \"\"\"\nHack\n\"\"\"\n") }
    }

    @Test func danglingSymlinkWritesThroughToItsDestination() throws {
        let f = try Fixture(write: false)
        let link = f.url(.herdr)
        let dest = f.home.appendingPathComponent("dotfiles/herdr.json")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dest)
        _ = f.switcher().apply([.herdr: FontChoice(family: "A", size: nil)])
        #expect((try FileManager.default.attributesOfItem(atPath: link.path))[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try String(contentsOf: dest, encoding: .utf8).contains("\"font\": \"A\""))
    }

    @Test func failedWriteIsExcludedFromBatchAndOthersStillUndo() throws {
        let f = try Fixture()
        let warpDir = f.url(.warp).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: warpDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: warpDir.path) }
        let s = f.switcher()
        let results = s.apply(all(FontChoice(family: "A", size: 12)))
        guard case .failed = results.first(where: { $0.target == .warp })?.outcome else { Issue.record("warp should fail"); return }
        let manifest = try #require(BackupStore(directory: f.backups).batches().last)
        #expect(!manifest.entries.contains { $0.target == .warp })
        let undo = try s.undoLast()
        #expect(undo.skippedModified.isEmpty)
        #expect(try f.read(.herdr) == Fixture.herdr)
    }

    @Test func manifestlessBatchDirsArePruned() throws {
        let f = try Fixture()
        let orphan = f.backups.appendingPathComponent("20260101-000000-000-999")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        _ = f.switcher().apply([.herdr: FontChoice(family: "A", size: nil)])
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }
}
