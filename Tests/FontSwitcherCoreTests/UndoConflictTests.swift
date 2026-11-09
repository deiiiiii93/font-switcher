import Foundation
import Testing
@testable import FontSwitcherCore

/// Undo must never silently lose the way back for an app whose file was edited after the switch.
@Suite struct UndoConflictTests {
    @Test func skippedAppKeepsItsBackupForADecision() throws {
        let f = try Fixture()
        let s = f.switcher()
        _ = s.apply(all(FontChoice(family: "A", size: 12)))
        try f.put("{\"user\": \"changed\"}", for: .herdr)

        let undo = try s.undoLast()
        #expect(undo.skippedModified == [.herdr])
        let seq = try #require(undo.pendingSequence)
        let kept = try #require(BackupStore(directory: f.backups).batches().last)
        #expect(kept.sequence == seq)
        #expect(kept.entries.map(\.target) == [.herdr])  // restored entries are gone, the skipped one stays
    }

    @Test func forceRestoreOverwritesTheLaterEdit() throws {
        let f = try Fixture()
        let s = f.switcher()
        _ = s.apply(all(FontChoice(family: "A", size: 12)))
        try f.put("{\"user\": \"changed\"}", for: .herdr)
        let undo = try s.undoLast()

        let forced = try s.forceRestore(sequence: undo.pendingSequence!, targets: [.herdr])
        #expect(forced.restored == [.herdr])
        #expect(try f.read(.herdr) == Fixture.herdr)
        #expect(f.batchCount() == 0)
    }

    @Test func discardKeepsCurrentFileAndDropsTheBackup() throws {
        let f = try Fixture()
        let s = f.switcher()
        _ = s.apply(all(FontChoice(family: "A", size: 12)))
        try f.put("{\"user\": \"changed\"}", for: .herdr)
        let undo = try s.undoLast()

        s.discardUndo(sequence: undo.pendingSequence!, targets: [.herdr])
        #expect(try f.read(.herdr) == "{\"user\": \"changed\"}")
        #expect(f.batchCount() == 0)
    }

    @Test func cleanUndoHasNoPendingDecision() throws {
        let f = try Fixture()
        let s = f.switcher()
        _ = s.apply(all(FontChoice(family: "A", size: 12)))
        let undo = try s.undoLast()
        #expect(undo.pendingSequence == nil)
        #expect(f.batchCount() == 0)
    }

    @Test func forceRestoreDeletesAFileTheSwitchCreated() throws {
        var f = try Fixture()
        try FileManager.default.removeItem(at: f.url(.kitty))
        f.installed = Set(TargetID.allCases)
        let s = f.switcher()
        _ = s.apply([.kitty: FontChoice(family: "A", size: nil)])
        try f.put("font_family B\n", for: .kitty)
        let undo = try s.undoLast()
        #expect(undo.skippedModified == [.kitty])
        _ = try s.forceRestore(sequence: undo.pendingSequence!, targets: [.kitty])
        #expect(!FileManager.default.fileExists(atPath: f.url(.kitty).path))
    }
}
