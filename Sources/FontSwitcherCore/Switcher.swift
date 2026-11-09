import AppKit
import Foundation

/// Applies font choices to app config files with backups, undo and reload signals.
public final class Switcher: Sendable {
    public static let keptBatches = 20

    public let home: URL
    public let backups: BackupStore
    let signaler: any ProcessSignaling
    let isInstalled: @Sendable (TargetID) -> Bool

    public init(home: URL, backupsDir: URL, signaler: any ProcessSignaling,
                isInstalled: @escaping @Sendable (TargetID) -> Bool) {
        self.home = home
        self.backups = BackupStore(directory: backupsDir)
        self.signaler = signaler
        self.isInstalled = isInstalled
    }

    /// Installed-app check backed by Launch Services.
    public static let launchServicesIsInstalled: @Sendable (TargetID) -> Bool = { id in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: TargetSpec.spec(for: id).bundleID) != nil
    }

    /// The config file for a target: the first existing candidate, else the default path.
    public func configURL(for target: TargetID) -> URL {
        let spec = TargetSpec.spec(for: target)
        let fm = FileManager.default
        for rel in spec.relativePaths {
            let u = home.appendingPathComponent(rel)
            if fm.fileExists(atPath: u.path) { return u }
        }
        return home.appendingPathComponent(spec.defaultRelativePath)
    }

    /// A target is detected when its app is installed or its config exists (spec D8).
    public func isDetected(_ target: TargetID) -> Bool {
        isInstalled(target) || FileManager.default.fileExists(atPath: configURL(for: target).path)
    }

    public func currentFont(for target: TargetID) -> FontChoice? {
        guard let data = try? Data(contentsOf: configURL(for: target)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return try? TargetSpec.spec(for: target).read(text)
    }

    /// Applies each choice to its target. Targets not in `choices` are never touched.
    /// One failing target does not stop the others (spec D7).
    public func apply(_ choices: [TargetID: FontChoice]) -> [ApplyResult] {
        struct Write {
            let target: TargetID
            let url: URL
            let original: Data?
            let new: Data
        }
        var results: [TargetID: ApplyResult.Outcome] = [:]
        var writes: [Write] = []
        let fm = FileManager.default

        for target in TargetID.allCases {
            guard let choice = choices[target] else { continue }
            let spec = TargetSpec.spec(for: target)
            let url = Self.writeLocation(for: configURL(for: target))
            do {
                let original: Data?
                let text: String
                if fm.fileExists(atPath: url.path) {
                    let data = try Data(contentsOf: url)
                    guard let s = String(data: data, encoding: .utf8) else { throw SwitcherError.notText(url.path) }
                    original = data
                    text = s
                } else {
                    guard isInstalled(target) else { results[target] = .skipped("not installed"); continue }
                    original = nil
                    text = spec.emptyDocument
                }
                let edited = try spec.edit(text, applying: choice)
                if original != nil, edited == text { results[target] = .unchanged; continue }
                writes.append(Write(target: target, url: url, original: original, new: Data(edited.utf8)))
            } catch {
                results[target] = .failed(Self.describe(error))
            }
        }

        if !writes.isEmpty {
            // 1. Stash originals and save the manifest BEFORE touching any config, so an interrupted
            //    apply is still undoable: a planned file that never got written fails the hash check
            //    and undo skips it.
            var pending: BackupStore.Pending?
            var planned: [BackupEntry] = []
            do {
                let batch = try backups.begin()
                pending = batch
                for w in writes {
                    let backupName = try w.original.map { try backups.stash($0, for: w.target, in: batch) }
                    planned.append(BackupEntry(target: w.target, path: w.url.path, existed: w.original != nil,
                                               backupFile: backupName, writtenSHA256: AtomicFile.sha256(w.new)))
                }
                try backups.commit(batch, entries: planned)
            } catch {
                if let pending { backups.discard(pending) }
                pending = nil
                // Without a backup we never write.
                for w in writes { results[w.target] = .failed("backup failed: \(Self.describe(error))") }
            }

            // 2. Write, then narrow the manifest to what was actually written.
            if let batch = pending {
                var written: [BackupEntry] = []
                for (w, entry) in zip(writes, planned) {
                    do {
                        try AtomicFile.write(w.new, to: w.url)
                        written.append(entry)
                        results[w.target] = .written(w.url.path)
                    } catch {
                        results[w.target] = .failed(Self.describe(error))
                    }
                }
                // If this fails the planned manifest stays, which is still safe (see step 1).
                try? backups.commit(batch, entries: written)
                backups.prune(keep: Self.keptBatches)
            }
        }

        for target in TargetID.allCases {
            if case .written = results[target], let sig = TargetSpec.spec(for: target).reloadSignal {
                signaler.signal(bundleID: TargetSpec.spec(for: target).bundleID, signal: sig)
            }
        }
        return TargetID.allCases.compactMap { t in results[t].map { ApplyResult(target: t, outcome: $0) } }
    }

    /// Restores the newest batch. Files changed since FontSwitcher wrote them are left alone (spec A4),
    /// but their backups are KEPT: the result's `pendingSequence` names the batch so the caller can
    /// ask the user, then `forceRestore` (overwrite the later edit) or `discardUndo` (keep it).
    @discardableResult
    public func undoLast() throws -> UndoResult {
        guard let batch = backups.stored().last else { throw SwitcherError.nothingToUndo }
        var result = UndoResult(restored: [], skippedModified: [])
        var keep: [BackupEntry] = []
        for e in batch.manifest.entries {
            let url = URL(fileURLWithPath: e.path)
            guard let current = try? Data(contentsOf: url), AtomicFile.sha256(current) == e.writtenSHA256 else {
                result.skippedModified.append(e.target)
                keep.append(e)
                continue
            }
            do {
                try restore(e, from: batch)
                result.restored.append(e.target)
            } catch {
                result.failed.append(e.target)
                keep.append(e)
            }
        }
        finish(batch, keeping: keep)
        if !result.skippedModified.isEmpty { result.pendingSequence = batch.manifest.sequence }
        signalReload(result.restored)
        return result
    }

    /// Restores the given targets from batch `sequence` even though their files changed after the switch.
    @discardableResult
    public func forceRestore(sequence: Int, targets: [TargetID]) throws -> UndoResult {
        guard let batch = backups.stored().first(where: { $0.manifest.sequence == sequence }) else {
            throw SwitcherError.nothingToUndo
        }
        var result = UndoResult(restored: [], skippedModified: [])
        var keep: [BackupEntry] = []
        for e in batch.manifest.entries {
            guard targets.contains(e.target) else { keep.append(e); continue }
            do {
                try restore(e, from: batch)
                result.restored.append(e.target)
            } catch {
                result.failed.append(e.target)
                keep.append(e)
            }
        }
        finish(batch, keeping: keep)
        signalReload(result.restored)
        return result
    }

    /// Keeps the current files for `targets` and drops their backups from batch `sequence`.
    public func discardUndo(sequence: Int, targets: [TargetID]) {
        guard let batch = backups.stored().first(where: { $0.manifest.sequence == sequence }) else { return }
        finish(batch, keeping: batch.manifest.entries.filter { !targets.contains($0.target) })
    }

    private func restore(_ e: BackupEntry, from batch: BackupStore.Batch) throws {
        let url = URL(fileURLWithPath: e.path)
        if e.existed, let name = e.backupFile {
            try AtomicFile.write(Data(contentsOf: batch.url.appendingPathComponent(name)), to: url)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Rewrites the batch with only the entries still needing a decision, or removes it when none remain.
    private func finish(_ batch: BackupStore.Batch, keeping entries: [BackupEntry]) {
        if entries.isEmpty {
            backups.remove(batch)
        } else {
            try? backups.commit(.init(sequence: batch.manifest.sequence, url: batch.url), entries: entries)
        }
    }

    private func signalReload(_ targets: [TargetID]) {
        for target in targets {
            let spec = TargetSpec.spec(for: target)
            if let sig = spec.reloadSignal { signaler.signal(bundleID: spec.bundleID, signal: sig) }
        }
    }

    /// Follows a symlink chain at the config path itself — including a dangling link whose
    /// destination doesn't exist yet — so writes land at the destination and the link survives.
    static func writeLocation(for url: URL) -> URL {
        var u = url
        for _ in 0..<16 {
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: u.path) else { break }
            u = dest.hasPrefix("/") ? URL(fileURLWithPath: dest) : u.deletingLastPathComponent().appendingPathComponent(dest)
        }
        return u.resolvingSymlinksInPath()
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case JSONCError.malformed(let offset, let reason): "could not parse settings (\(reason) at byte \(offset))"
        case TOMLError.malformed(let line, let reason): "could not parse TOML (\(reason) at line \(line + 1))"
        case SwitcherError.notText: "file is not UTF-8 text"
        case SwitcherError.invalidFamily: "font family name contains control characters"
        default: error.localizedDescription
        }
    }
}
