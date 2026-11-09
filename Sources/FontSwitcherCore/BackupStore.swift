import Foundation

public struct BackupEntry: Codable, Sendable, Equatable {
    public let target: TargetID
    /// Resolved (symlink-free) path that was written.
    public let path: String
    public let existed: Bool
    /// File name of the copy inside the batch directory (nil when the file did not exist).
    public let backupFile: String?
    /// SHA-256 of the content FontSwitcher wrote; undo only restores while this still matches.
    public let writtenSHA256: String
}

public struct BackupManifest: Codable, Sendable {
    public let sequence: Int
    public let created: Date
    public let entries: [BackupEntry]
}

/// One directory per apply: `<yyyyMMdd-HHmmss-SSS>-<seq>/manifest.json` plus copies of the originals.
/// Ordering is by `sequence` (spec A5), never by directory name.
public struct BackupStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    struct Batch {
        let manifest: BackupManifest
        let url: URL
    }

    struct Pending {
        let sequence: Int
        let url: URL
    }

    public func batches() -> [BackupManifest] { stored().map(\.manifest) }

    func stored() -> [Batch] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let m = try? decoder.decode(BackupManifest.self, from: data) else { return nil }
            return Batch(manifest: m, url: dir)
        }.sorted { $0.manifest.sequence < $1.manifest.sequence }
    }

    func begin() throws -> Pending {
        let fm = FileManager.default
        // Sequence comes from committed manifests; manifest-less leftovers are pruned separately.
        let seq = (stored().last?.manifest.sequence ?? 0) + 1
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let url = directory.appendingPathComponent("\(f.string(from: Date()))-\(seq)")
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return Pending(sequence: seq, url: url)
    }

    func stash(_ data: Data, for target: TargetID, in batch: Pending) throws -> String {
        let name = "\(target.rawValue).bak"
        try data.write(to: batch.url.appendingPathComponent(name))
        return name
    }

    /// Writes the manifest, or removes the batch when nothing was written.
    func commit(_ batch: Pending, entries: [BackupEntry]) throws {
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: batch.url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = BackupManifest(sequence: batch.sequence, created: Date(), entries: entries)
        try encoder.encode(manifest).write(to: batch.url.appendingPathComponent("manifest.json"), options: .atomic)
    }

    /// Keeps the newest `keep` batches and removes directories left without a manifest
    /// (an apply interrupted before its first manifest write).
    func prune(keep: Int) {
        let fm = FileManager.default
        let all = stored()
        for b in all.dropLast(keep) { try? fm.removeItem(at: b.url) }
        let live = Set(all.map { $0.url.standardizedFileURL.path })
        let dirs = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for d in dirs where !live.contains(d.standardizedFileURL.path) {
            if !fm.fileExists(atPath: d.appendingPathComponent("manifest.json").path) { try? fm.removeItem(at: d) }
        }
    }

    func discard(_ batch: Pending) { try? FileManager.default.removeItem(at: batch.url) }

    func remove(_ batch: Batch) { try? FileManager.default.removeItem(at: batch.url) }
}
