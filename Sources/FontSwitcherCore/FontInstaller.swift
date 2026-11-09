import Foundation

public enum InstallResult: Equatable, Sendable {
    case installed(URL)
    case skipped(URL, reason: String)
}

public enum FontInstallerError: Error, Equatable, Sendable {
    case notUserInstalled
    case sharedFile(otherFamily: String)
}

public enum FontInstaller {
    static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]

    public static func install(_ urls: [URL], into dir: URL) -> [InstallResult] {
        let fm = FileManager.default
        return urls.map { src in
            guard fontExtensions.contains(src.pathExtension.lowercased()) else {
                return .skipped(src, reason: "not a font file")
            }
            let dest = dir.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { return .skipped(src, reason: "already installed") }
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dest)
                return .installed(dest)
            } catch {
                return .skipped(src, reason: "copy failed: \(error.localizedDescription)")
            }
        }
    }

    public static func remove(family: FontFamily, catalog: [FontFamily], userFontsDir: URL,
                              trash: (URL) throws -> Void) throws {
        guard !family.faceURLs.isEmpty, family.faceURLs.allSatisfy({ isInside($0, dir: userFontsDir) }) else {
            throw FontInstallerError.notUserInstalled
        }
        let mine = Set(family.faceURLs.map(canonical))
        for other in catalog where other.name != family.name {
            if other.faceURLs.contains(where: { mine.contains(canonical($0)) }) {
                throw FontInstallerError.sharedFile(otherFamily: other.name)
            }
        }
        var seen = Set<URL>()
        for url in family.faceURLs where seen.insert(canonical(url)).inserted {
            try trash(url)
        }
    }

    static func canonical(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }

    static func isInside(_ url: URL, dir: URL) -> Bool {
        let d = canonical(dir).pathComponents
        let f = canonical(url).pathComponents
        return f.count > d.count && Array(f.prefix(d.count)) == d
    }
}
