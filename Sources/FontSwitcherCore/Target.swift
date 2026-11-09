import Foundation

/// Where each app keeps its font settings and how to edit them (spec Contracts → Target table).
public struct TargetSpec: Sendable {
    public enum Format: Sendable {
        case jsonc(familyKeys: [String], sizeKey: String, familyIsList: Bool)
        case ghostty
        case kitty
        case toml(table: String, familyKey: String, sizeKey: String)
    }

    public let id: TargetID
    public let bundleID: String
    /// Candidate config paths relative to home, in priority order; the first is created when none exist.
    public let relativePaths: [String]
    public let format: Format
    /// Signal that makes a running instance reload its config, if any.
    public let reloadSignal: Int32?
    /// User-facing caveat about how the change takes effect.
    public let note: String?

    public var defaultRelativePath: String { relativePaths[0] }

    public static func spec(for id: TargetID) -> TargetSpec {
        switch id {
        case .vscode:
            TargetSpec(id: id, bundleID: "com.microsoft.VSCode",
                       relativePaths: ["Library/Application Support/Code/User/settings.json"],
                       format: .jsonc(familyKeys: ["editor.fontFamily", "terminal.integrated.fontFamily"],
                                      sizeKey: "editor.fontSize", familyIsList: true),
                       reloadSignal: nil, note: nil)
        case .cursor:
            TargetSpec(id: id, bundleID: "com.todesktop.230313mzl4w4u92",
                       relativePaths: ["Library/Application Support/Cursor/User/settings.json"],
                       format: .jsonc(familyKeys: ["editor.fontFamily", "terminal.integrated.fontFamily"],
                                      sizeKey: "editor.fontSize", familyIsList: true),
                       reloadSignal: nil, note: nil)
        case .ghostty:
            TargetSpec(id: id, bundleID: "com.mitchellh.ghostty",
                       relativePaths: ["Library/Application Support/com.mitchellh.ghostty/config.ghostty",
                                       "Library/Application Support/com.mitchellh.ghostty/config",
                                       ".config/ghostty/config.ghostty",
                                       ".config/ghostty/config"],
                       format: .ghostty, reloadSignal: SIGUSR2,
                       note: "Font family changes apply to new windows and tabs.")
        case .herdr:
            TargetSpec(id: id, bundleID: "dev.herdr.app",
                       relativePaths: [".config/herdr-app/settings.json"],
                       format: .jsonc(familyKeys: ["font"], sizeKey: "font_size", familyIsList: false),
                       reloadSignal: nil,
                       note: "Size is in px at zoom 1; a layout's own font overrides this.")
        case .kitty:
            TargetSpec(id: id, bundleID: "net.kovidgoyal.kitty",
                       relativePaths: [".config/kitty/kitty.conf"],
                       format: .kitty, reloadSignal: SIGUSR1, note: nil)
        case .warp:
            TargetSpec(id: id, bundleID: "dev.warp.Warp-Stable",
                       relativePaths: [".warp/settings.toml"],
                       format: .toml(table: "appearance.text", familyKey: "font_name", sizeKey: "font_size"),
                       reloadSignal: nil, note: nil)
        }
    }

    /// Initial content when the config file does not exist yet.
    var emptyDocument: String {
        if case .jsonc = format { return "{}" }
        return ""
    }

    /// Returns `text` with the choice applied. Throws when the file cannot be parsed.
    public func edit(_ text: String, applying choice: FontChoice) throws -> String {
        // Family names come from font files and free-text fields: untrusted. A line break in a
        // line-based config would inject directives (e.g. Ghostty `command = …`), so reject any
        // control or line/paragraph-separator character for every target.
        if let family = choice.family, Self.hasControlCharacters(family) { throw SwitcherError.invalidFamily }
        var out = text
        switch format {
        case let .jsonc(familyKeys, sizeKey, familyIsList):
            if let family = choice.family {
                for key in familyKeys {
                    let value = familyIsList
                        ? FontList.replacingPrimary(in: try JSONCEditor.topLevelString(key, in: out) ?? "", with: family)
                        : family
                    out = try JSONCEditor.setTopLevel(key, to: .string(value), in: out)
                }
            }
            if let size = choice.size { out = try JSONCEditor.setTopLevel(sizeKey, to: .number(size), in: out) }
        case .ghostty:
            if let family = choice.family {
                out = LineConfigEditor.set("font-family", to: family, in: out, style: .ghostty, occurrence: .first)
            }
            if let size = choice.size {
                out = LineConfigEditor.set("font-size", to: JSONCEditor.formatNumber(size), in: out, style: .ghostty, occurrence: .last)
            }
        case .kitty:
            if let family = choice.family {
                let existing = LineConfigEditor.value("font_family", in: out, style: .kitty, occurrence: .last)
                out = LineConfigEditor.set("font_family", to: LineValue.kittyFamily(family, existingRaw: existing),
                                           in: out, style: .kitty, occurrence: .last)
            }
            if let size = choice.size {
                out = LineConfigEditor.set("font_size", to: JSONCEditor.formatNumber(size), in: out, style: .kitty, occurrence: .last)
            }
        case let .toml(table, familyKey, sizeKey):
            if let family = choice.family { out = try TOMLEditor.set(familyKey, to: .string(family), inTable: table, in: out) }
            if let size = choice.size { out = try TOMLEditor.set(sizeKey, to: .float(size), inTable: table, in: out) }
        }
        return out
    }

    static func hasControlCharacters(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) || $0 == "\u{2028}" || $0 == "\u{2029}" }
    }

    /// Reads the primary family and size currently configured.
    public func read(_ text: String) throws -> FontChoice {
        switch format {
        case let .jsonc(familyKeys, sizeKey, familyIsList):
            let raw = try JSONCEditor.topLevelString(familyKeys[0], in: text)
            let family = familyIsList ? raw.flatMap(FontList.primary(of:)) : raw
            return FontChoice(family: family, size: try JSONCEditor.topLevelNumber(sizeKey, in: text))
        case .ghostty:
            let family = LineConfigEditor.value("font-family", in: text, style: .ghostty, occurrence: .first)
                .map(LineValue.ghosttyFamily(from:))
            let size = LineConfigEditor.value("font-size", in: text, style: .ghostty, occurrence: .last).flatMap(Double.init)
            return FontChoice(family: family, size: size)
        case .kitty:
            let family = LineConfigEditor.value("font_family", in: text, style: .kitty, occurrence: .last)
                .map(LineValue.kittyFamilyName(from:))
            let size = LineConfigEditor.value("font_size", in: text, style: .kitty, occurrence: .last).flatMap(Double.init)
            return FontChoice(family: family, size: size)
        case let .toml(table, familyKey, sizeKey):
            return FontChoice(family: TOMLEditor.value(familyKey, inTable: table, in: text),
                              size: TOMLEditor.value(sizeKey, inTable: table, in: text).flatMap(Double.init))
        }
    }
}
