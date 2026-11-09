import Foundation
import Testing
@testable import FontSwitcherCore

final class FakeSignaler: ProcessSignaling, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(String, Int32)] = []
    var calls: [(String, Int32)] { lock.withLock { _calls } }
    func signal(bundleID: String, signal: Int32) { lock.withLock { _calls.append((bundleID, signal)) } }
}

struct Fixture {
    let home: URL
    let backups: URL
    let signaler = FakeSignaler()
    var installed: Set<TargetID> = Set(TargetID.allCases)

    static let vscode = "{\n    \"workbench.colorTheme\": \"Dark\",\n    \"editor.fontFamily\": \"Sono, Sarasa Mono Slab CL\",\n    \"editor.fontSize\": 14,\n    \"terminal.integrated.fontFamily\": \"monospace\"\n}"
    static let cursor = "{\n  // comment\n  \"editor.fontFamily\": \"Zed Mono, Sarasa Mono Slab CL\",\n  \"editor.fontSize\": 14,\n}\n"
    static let ghostty = "theme = dark\nfont-family = Berkeley Mono"
    static let herdr = "{\n  \"zoom\": 1,\n  \"font\": \"Berkeley Mono\",\n  \"font_size\": 13\n}"
    static let kitty = "# font_family Old\n# BEGIN_KITTY_FONTS\nfont_family      family=\"Zed Mono\"\n# END_KITTY_FONTS"
    static let warp = "[appearance.text]\nai_font_name = \"Sono\"\nfont_name = \"Berkeley Mono Variable\"\nfont_size = 14.0\n"

    init(write: Bool = true) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fs-test-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        backups = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if write {
            for (id, text) in [(TargetID.vscode, Self.vscode), (.cursor, Self.cursor), (.ghostty, Self.ghostty),
                               (.herdr, Self.herdr), (.kitty, Self.kitty), (.warp, Self.warp)] {
                try put(text, for: id)
            }
        }
    }

    func url(_ id: TargetID) -> URL { home.appendingPathComponent(TargetSpec.spec(for: id).defaultRelativePath) }

    func put(_ text: String, for id: TargetID) throws {
        let u = url(id)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: u)
    }

    func read(_ id: TargetID) throws -> String { try String(contentsOf: url(id), encoding: .utf8) }

    func switcher() -> Switcher {
        let inst = installed
        return Switcher(home: home, backupsDir: backups, signaler: signaler, isInstalled: { inst.contains($0) })
    }

    func batchCount() -> Int { BackupStore(directory: backups).batches().count }
}

func all(_ c: FontChoice) -> [TargetID: FontChoice] { Dictionary(uniqueKeysWithValues: TargetID.allCases.map { ($0, c) }) }

@Suite struct SwitcherTests {
    @Test func appliesToEveryTargetSurgically() throws {
        let f = try Fixture()
        let results = f.switcher().apply(all(FontChoice(family: "Berkeley Mono", size: 15)))
        #expect(results.allSatisfy { if case .written = $0.outcome { true } else { false } })
        #expect(try f.read(.vscode) == "{\n    \"workbench.colorTheme\": \"Dark\",\n    \"editor.fontFamily\": \"Berkeley Mono, Sarasa Mono Slab CL\",\n    \"editor.fontSize\": 15,\n    \"terminal.integrated.fontFamily\": \"Berkeley Mono\"\n}")
        #expect(try f.read(.cursor) == "{\n  // comment\n  \"editor.fontFamily\": \"Berkeley Mono, Sarasa Mono Slab CL\",\n  \"editor.fontSize\": 15,\n  \"terminal.integrated.fontFamily\": \"Berkeley Mono\",\n}\n")
        #expect(try f.read(.ghostty) == "theme = dark\nfont-family = Berkeley Mono\nfont-size = 15\n")
        #expect(try f.read(.herdr) == "{\n  \"zoom\": 1,\n  \"font\": \"Berkeley Mono\",\n  \"font_size\": 15\n}")
        #expect(try f.read(.kitty) == "# font_family Old\n# BEGIN_KITTY_FONTS\nfont_family      family=\"Berkeley Mono\"\n# END_KITTY_FONTS\nfont_size 15\n")
        #expect(try f.read(.warp) == "[appearance.text]\nai_font_name = \"Sono\"\nfont_name = \"Berkeley Mono\"\nfont_size = 15.0\n")
        #expect(f.batchCount() == 1)
    }

    @Test func nilSizeLeavesSizesUntouched() throws {
        let f = try Fixture()
        _ = f.switcher().apply(all(FontChoice(family: "Zed Mono", size: nil)))
        #expect(try f.read(.ghostty) == "theme = dark\nfont-family = Zed Mono")
        #expect(try f.read(.warp).contains("font_size = 14.0"))
    }

    @Test func targetsAbsentFromChoicesUntouched() throws {
        let f = try Fixture()
        _ = f.switcher().apply([.vscode: FontChoice(family: "X", size: nil)])
        #expect(try f.read(.cursor) == Fixture.cursor)
        #expect(try f.read(.ghostty) == Fixture.ghostty)
        #expect(try f.read(.warp) == Fixture.warp)
        #expect(try f.read(.vscode).contains("\"X, Sarasa Mono Slab CL\""))
    }

    @Test func unparseableTargetFailsAndIsNotWritten() throws {
        let f = try Fixture()
        try f.put("{ broken", for: .vscode)
        let results = f.switcher().apply(all(FontChoice(family: "X", size: 12)))
        let vs = results.first { $0.target == .vscode }!
        guard case .failed = vs.outcome else { Issue.record("expected failure"); return }
        #expect(try f.read(.vscode) == "{ broken")
        #expect(try f.read(.herdr).contains("\"font\": \"X\""))
        let manifest = try #require(BackupStore(directory: f.backups).batches().last)
        #expect(!manifest.entries.contains { $0.target == .vscode })
    }

    @Test func unchangedApplyCreatesNoBatchAndNoSignal() throws {
        let f = try Fixture()
        let s = f.switcher()
        _ = s.apply(all(FontChoice(family: "A", size: 12)))
        let signals = f.signaler.calls.count
        let second = s.apply(all(FontChoice(family: "A", size: 12)))
        #expect(second.allSatisfy { $0.outcome == .unchanged })
        #expect(f.batchCount() == 1)
        #expect(f.signaler.calls.count == signals)
    }

    @Test func undoRestoresByteForByteAndDeletesCreatedFiles() throws {
        var f = try Fixture()
        try FileManager.default.removeItem(at: f.url(.kitty))
        f.installed = Set(TargetID.allCases)
        let s = f.switcher()
        _ = s.apply(all(FontChoice(family: "A", size: 12)))
        #expect(FileManager.default.fileExists(atPath: f.url(.kitty).path))
        let undo = try s.undoLast()
        #expect(Set(undo.restored) == Set(TargetID.allCases))
        #expect(undo.skippedModified.isEmpty)
        #expect(try f.read(.vscode) == Fixture.vscode)
        #expect(try f.read(.warp) == Fixture.warp)
        #expect(!FileManager.default.fileExists(atPath: f.url(.kitty).path))
        #expect(f.batchCount() == 0)
        #expect(throws: SwitcherError.nothingToUndo) { try s.undoLast() }
    }

    @Test func undoIsLIFOAcrossRapidApplies() throws {
        let f = try Fixture()
        let s = f.switcher()
        _ = s.apply(all(FontChoice(family: "A", size: 12)))
        _ = s.apply(all(FontChoice(family: "B", size: 13)))
        _ = try s.undoLast()
        #expect(try f.read(.herdr).contains("\"font\": \"A\""))
        _ = try s.undoLast()
        #expect(try f.read(.herdr) == Fixture.herdr)
    }

    @Test func undoSkipsFilesEditedAfterTheSwitch() throws {
        let f = try Fixture()
        let s = f.switcher()
        _ = s.apply(all(FontChoice(family: "A", size: 12)))
        try f.put("{\"user\": \"changed\"}", for: .herdr)
        let undo = try s.undoLast()
        #expect(undo.skippedModified == [.herdr])
        #expect(try f.read(.herdr) == "{\"user\": \"changed\"}")
        #expect(try f.read(.ghostty) == Fixture.ghostty)
    }

    @Test func symlinkedConfigStaysASymlink() throws {
        let f = try Fixture()
        let dotfile = f.home.appendingPathComponent("dotfiles/ghostty.conf")
        try FileManager.default.createDirectory(at: dotfile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Fixture.ghostty.utf8).write(to: dotfile)
        try FileManager.default.removeItem(at: f.url(.ghostty))
        try FileManager.default.createSymbolicLink(at: f.url(.ghostty), withDestinationURL: dotfile)
        let s = f.switcher()
        _ = s.apply([.ghostty: FontChoice(family: "Zed Mono", size: nil)])
        let attrs = try FileManager.default.attributesOfItem(atPath: f.url(.ghostty).path)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try String(contentsOf: dotfile, encoding: .utf8) == "theme = dark\nfont-family = Zed Mono")
        _ = try s.undoLast()
        #expect(try String(contentsOf: dotfile, encoding: .utf8) == Fixture.ghostty)
        #expect((try FileManager.default.attributesOfItem(atPath: f.url(.ghostty).path))[.type] as? FileAttributeType == .typeSymbolicLink)
    }

    @Test func preservesPermissions() throws {
        let f = try Fixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.url(.warp).path)
        _ = f.switcher().apply([.warp: FontChoice(family: "Z", size: nil)])
        let perms = try FileManager.default.attributesOfItem(atPath: f.url(.warp).path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func reloadSignalsOnlyForWrittenTerminals() throws {
        let f = try Fixture()
        _ = f.switcher().apply([.kitty: FontChoice(family: "A", size: nil), .ghostty: FontChoice(family: "A", size: nil),
                                .vscode: FontChoice(family: "A", size: nil)])
        let calls = f.signaler.calls
        #expect(calls.count == 2)
        #expect(calls.contains { $0.0 == "net.kovidgoyal.kitty" && $0.1 == SIGUSR1 })
        #expect(calls.contains { $0.0 == "com.mitchellh.ghostty" && $0.1 == SIGUSR2 })
    }

    @Test func missingFileCreatedOnlyWhenInstalled() throws {
        var f = try Fixture(write: false)
        f.installed = [.herdr]
        let results = f.switcher().apply(all(FontChoice(family: "A", size: 12)))
        #expect(results.first { $0.target == .kitty }?.outcome == .skipped("not installed"))
        #expect(!FileManager.default.fileExists(atPath: f.url(.kitty).path))
        #expect(try f.read(.herdr) == "{\n  \"font\": \"A\",\n  \"font_size\": 12\n}")
    }

    @Test func keepsNewestTwentyBatches() throws {
        let f = try Fixture()
        let s = f.switcher()
        for i in 0..<22 { _ = s.apply([.herdr: FontChoice(family: "F\(i)", size: nil)]) }
        let batches = BackupStore(directory: f.backups).batches()
        #expect(batches.count == 20)
        #expect(batches.map(\.sequence) == Array(3...22))
    }

    @Test func readsCurrentFonts() throws {
        let f = try Fixture()
        let s = f.switcher()
        #expect(s.currentFont(for: .vscode) == FontChoice(family: "Sono", size: 14))
        #expect(s.currentFont(for: .ghostty) == FontChoice(family: "Berkeley Mono", size: nil))
        #expect(s.currentFont(for: .kitty) == FontChoice(family: "Zed Mono", size: nil))
        #expect(s.currentFont(for: .warp) == FontChoice(family: "Berkeley Mono Variable", size: 14))
        #expect(s.currentFont(for: .herdr) == FontChoice(family: "Berkeley Mono", size: 13))
    }

    @Test func ghosttyPathPrefersAppSupport() throws {
        let f = try Fixture(write: false)
        let xdg = f.home.appendingPathComponent(".config/ghostty/config")
        try FileManager.default.createDirectory(at: xdg.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: xdg)
        #expect(f.switcher().configURL(for: .ghostty).path == xdg.path)
        try f.put("", for: .ghostty)
        #expect(f.switcher().configURL(for: .ghostty).path == f.url(.ghostty).path)
    }
}

@Suite struct ProfileTests {
    @Test func overridesFallBackToProfileFields() {
        let p = Profile(name: "Work", family: "Berkeley Mono", size: 14,
                        overrides: [.ghostty: FontChoice(family: nil, size: 16), .herdr: FontChoice(family: "Geist Mono", size: nil)])
        #expect(p.choice(for: .ghostty) == FontChoice(family: "Berkeley Mono", size: 16))
        #expect(p.choice(for: .herdr) == FontChoice(family: "Geist Mono", size: 14))
        #expect(p.choice(for: .vscode) == FontChoice(family: "Berkeley Mono", size: 14))
    }

    @Test func codableRoundTrip() throws {
        let p = Profile(name: "W", family: "A", size: nil, overrides: [.kitty: FontChoice(family: "B", size: 1)])
        let data = try JSONEncoder().encode(p)
        #expect(String(decoding: data, as: UTF8.self).contains("\"kitty\""))
        #expect(try JSONDecoder().decode(Profile.self, from: data) == p)
    }
}
