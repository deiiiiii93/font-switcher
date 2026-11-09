import CryptoKit
import Foundation

enum AtomicFile {
    /// Writes `data` to `url` via a temp file in the same directory + rename(2).
    /// `url` must already be symlink-resolved so a symlink at the original path survives.
    /// Existing POSIX permissions are preserved; parent directories are created.
    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let perms = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).fontswitcher-\(UUID().uuidString)")
        try data.write(to: tmp)
        do {
            // Flush to stable storage before the rename so a power loss can't leave an empty config.
            let fh = try FileHandle(forWritingTo: tmp)
            _ = fcntl(fh.fileDescriptor, F_FULLFSYNC)
            try fh.close()
            if let perms { try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: tmp.path) }
            guard rename(tmp.path, url.path) == 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path,
                                                               NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
