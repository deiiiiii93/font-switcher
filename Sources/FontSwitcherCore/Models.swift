import Foundation

public enum TargetID: String, Codable, CaseIterable, Sendable, Identifiable, CodingKeyRepresentable {
    case vscode, cursor, ghostty, herdr, kitty, warp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vscode: "VS Code"
        case .cursor: "Cursor"
        case .ghostty: "Ghostty"
        case .herdr: "Herdr"
        case .kitty: "kitty"
        case .warp: "Warp"
        }
    }

    public var isTerminal: Bool { [.ghostty, .herdr, .kitty, .warp].contains(self) }
}

/// A family and/or size to apply. A nil field means "leave as is".
public struct FontChoice: Codable, Hashable, Sendable {
    public var family: String?
    public var size: Double?

    public init(family: String?, size: Double?) {
        self.family = family
        self.size = size
    }
}

public struct Profile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var family: String
    public var size: Double?
    public var overrides: [TargetID: FontChoice]

    public init(id: UUID = UUID(), name: String, family: String, size: Double?, overrides: [TargetID: FontChoice] = [:]) {
        self.id = id
        self.name = name
        self.family = family
        self.size = size
        self.overrides = overrides
    }

    /// Override fields win; nil override fields fall back to the profile's own fields.
    public func choice(for target: TargetID) -> FontChoice {
        let o = overrides[target]
        return FontChoice(family: o?.family ?? family, size: o?.size ?? size)
    }

    public func choices(for targets: some Sequence<TargetID>) -> [TargetID: FontChoice] {
        Dictionary(uniqueKeysWithValues: targets.map { ($0, choice(for: $0)) })
    }
}

public struct ApplyResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case written(String)
        case unchanged
        case skipped(String)
        case failed(String)
    }

    public let target: TargetID
    public let outcome: Outcome
}

public struct UndoResult: Sendable, Equatable {
    public var restored: [TargetID]
    public var skippedModified: [TargetID]
    /// Restore attempted but failed (I/O error); the batch keeps these for a retry.
    public var failed: [TargetID] = []
    /// Set when `skippedModified` is non-empty: the backup batch still holding those apps' originals,
    /// for `Switcher.forceRestore` / `discardUndo` after asking the user.
    public var pendingSequence: Int?
}

public enum SwitcherError: Error, Equatable, Sendable {
    case nothingToUndo
    case notText(String)
    /// The family name contains control or line-separator characters (it would inject config lines).
    case invalidFamily
}
