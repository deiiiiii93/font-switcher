import Foundation
import Testing
@testable import FontSwitcherCore

@Suite struct FontInstallerTests {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("fi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func family(_ name: String, _ urls: [URL], user: Bool = true) -> FontFamily {
        FontFamily(name: name, isMonospaced: true, faceURLs: urls, isUserInstalled: user)
    }

    @Test func installCopiesValidSkipsInvalidAndDuplicates() throws {
        let src = try tempDir(), dest = try tempDir().appendingPathComponent("Fonts")
        let a = src.appendingPathComponent("A.ttf"), b = src.appendingPathComponent("B.OTF")
        let c = src.appendingPathComponent("notes.txt")
        for u in [a, b, c] { try Data("x".utf8).write(to: u) }
        let r1 = FontInstaller.install([a, b, c], into: dest)
        #expect(r1[0] == .installed(dest.appendingPathComponent("A.ttf")))
        #expect(r1[1] == .installed(dest.appendingPathComponent("B.OTF")))
        #expect(r1[2] == .skipped(c, reason: "not a font file"))
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("B.OTF").path))
        let r2 = FontInstaller.install([a], into: dest)
        #expect(r2 == [.skipped(a, reason: "already installed")])
    }

    @Test func removeTrashesEachFace() throws {
        let dir = try tempDir()
        let f1 = dir.appendingPathComponent("a.ttf"), f2 = dir.appendingPathComponent("b.ttf")
        for u in [f1, f2] { try Data("x".utf8).write(to: u) }
        nonisolated(unsafe) var trashed: [String] = []
        let foo = family("Foo", [f1, f2])
        try FontInstaller.remove(family: foo, catalog: [foo], userFontsDir: dir) { trashed.append($0.lastPathComponent) }
        #expect(trashed.sorted() == ["a.ttf", "b.ttf"])
    }

    @Test func removeRefusesFaceOutsideUserDir() throws {
        let dir = try tempDir(), other = try tempDir()
        let f1 = dir.appendingPathComponent("a.ttf"), f2 = other.appendingPathComponent("b.ttf")
        nonisolated(unsafe) var count = 0
        #expect(throws: FontInstallerError.notUserInstalled) {
            try FontInstaller.remove(family: family("Foo", [f1, f2]), catalog: [], userFontsDir: dir) { _ in count += 1 }
        }
        #expect(count == 0)
    }

    @Test func removeRefusesSharedCollection() throws {
        let dir = try tempDir()
        let ttc = dir.appendingPathComponent("c.ttc")
        let foo = family("Foo", [ttc]), bar = family("Bar", [ttc])
        nonisolated(unsafe) var count = 0
        #expect(throws: FontInstallerError.sharedFile(otherFamily: "Bar")) {
            try FontInstaller.remove(family: foo, catalog: [foo, bar], userFontsDir: dir) { _ in count += 1 }
        }
        #expect(count == 0)
    }

    @Test func catalogListsMenlo() {
        let fams = FontCatalog.families()
        #expect(!fams.isEmpty)
        let menlo = fams.first { $0.name == "Menlo" }
        #expect(menlo?.isMonospaced == true)
        #expect(menlo?.isUserInstalled == false)
    }
}
