import CoreText
import Foundation

public struct FontFamily: Hashable, Sendable, Identifiable {
    public let name: String
    public let isMonospaced: Bool
    public let faceURLs: [URL]
    public let isUserInstalled: Bool
    public var id: String { name }

    public init(name: String, isMonospaced: Bool, faceURLs: [URL], isUserInstalled: Bool) {
        self.name = name
        self.isMonospaced = isMonospaced
        self.faceURLs = faceURLs
        self.isUserInstalled = isUserInstalled
    }
}

public enum FontCatalog {
    public static var userFontsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts", isDirectory: true)
    }

    public static func families(userFontsDir: URL = FontCatalog.userFontsDir) -> [FontFamily] {
        let names = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        var result: [FontFamily] = []
        for name in names where !name.hasPrefix(".") {
            let attrs = [kCTFontFamilyNameAttribute: name] as CFDictionary
            let query = CTFontDescriptorCreateWithAttributes(attrs)
            let faces = (CTFontDescriptorCreateMatchingFontDescriptors(query, nil) as? [CTFontDescriptor]) ?? []
            var urls: [URL] = []
            var mono = false
            for face in faces {
                if let url = CTFontDescriptorCopyAttribute(face, kCTFontURLAttribute) as? URL, !urls.contains(url) {
                    urls.append(url)
                }
                if let traits = CTFontDescriptorCopyAttribute(face, kCTFontTraitsAttribute) as? [CFString: Any],
                   let sym = traits[kCTFontSymbolicTrait] as? NSNumber,
                   CTFontSymbolicTraits(rawValue: sym.uint32Value).contains(.traitMonoSpace) {
                    mono = true
                }
            }
            let user = !urls.isEmpty && urls.allSatisfy { FontInstaller.isInside($0, dir: userFontsDir) }
            result.append(FontFamily(name: name, isMonospaced: mono, faceURLs: urls, isUserInstalled: user))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
