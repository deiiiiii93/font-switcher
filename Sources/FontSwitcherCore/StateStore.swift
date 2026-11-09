import Foundation

/// Everything the app persists (spec D11).
public struct AppState: Codable, Equatable, Sendable {
    public var profiles: [Profile] = []
    public var favorites: [String] = []
    /// nil = "every detected target" (spec D8 default).
    public var enabledTargets: Set<TargetID>?
    public var activeProfileID: UUID?
    public var freshDay = FreshDayState()
    /// True after the built-in starter profiles have been offered once.
    public var starterProfilesInstalled = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case profiles, favorites, enabledTargets, activeProfileID, freshDay, starterProfilesInstalled
    }

    // Every key optional, so older or hand-edited files still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
        enabledTargets = try c.decodeIfPresent(Set<TargetID>.self, forKey: .enabledTargets)
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        freshDay = try c.decodeIfPresent(FreshDayState.self, forKey: .freshDay) ?? FreshDayState()
        starterProfilesInstalled = try c.decodeIfPresent(Bool.self, forKey: .starterProfilesInstalled) ?? false
    }
}

public struct StateStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Loads state; a missing file gives defaults, a corrupt one is moved aside and defaults are returned.
    public func load() -> AppState {
        guard let data = try? Data(contentsOf: url) else { return AppState() }
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let aside = url.deletingLastPathComponent().appendingPathComponent("state.corrupt-\(f.string(from: Date())).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return AppState()
        }
    }

    public func save(_ state: AppState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(state), to: url)
    }
}
