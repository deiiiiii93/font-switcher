import Foundation

/// "Fresh Day": one random coding font per local day (spec D10/A10).
public enum FreshDay {
    /// Local calendar day as `yyyy-MM-dd`.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = gregorian(in: calendar).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Favorites when there are at least two, otherwise every monospaced family.
    public static func pool(favorites: [String], monospaced: [String]) -> [String] {
        Set(favorites).count >= 2 ? favorites : monospaced
    }

    /// Deterministic pick for the local day of `date`: the same day and pool always give the same family,
    /// whatever the pool's order. `excluding` is avoided whenever another family is available.
    public static func pick(for date: Date, calendar: Calendar, pool: [String], excluding: String?, salt: UInt64 = 0) -> String? {
        var candidates = Array(Set(pool)).sorted()
        if let excluding, candidates.count > 1 { candidates.removeAll { $0 == excluding } }
        guard !candidates.isEmpty else { return nil }
        let index = Int(splitMix64(seed: dayNumber(date, calendar: calendar) &+ salt &* 0x9E37_79B9_7F4A_7C15) % UInt64(candidates.count))
        return candidates[index]
    }

    /// Days since 1970-01-01 for the *local* calendar day (so the seed flips at local midnight).
    static func dayNumber(_ date: Date, calendar: Calendar) -> UInt64 {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let c = gregorian(in: calendar).dateComponents([.year, .month, .day], from: date)
        let midnight = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? date
        return UInt64(bitPattern: Int64((midnight.timeIntervalSince1970 / 86_400).rounded(.down)))
    }

    /// Only the caller's time zone matters: the system calendar may be Japanese/Buddhist/Hebrew,
    /// whose year/month/day would otherwise leak into the `yyyy-MM-dd` key and the daily seed.
    static func gregorian(in calendar: Calendar) -> Calendar {
        var g = Calendar(identifier: .gregorian)
        g.timeZone = calendar.timeZone
        return g
    }

    static func splitMix64(seed: UInt64) -> UInt64 {
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct FreshDayRecord: Codable, Equatable, Sendable {
    public var day: String
    public var family: String
}

public struct FreshDayState: Codable, Equatable, Sendable {
    public static let historyLimit = 30

    /// Off by default (spec A7): launching never writes configs unless the user opts in.
    public var enabled: Bool
    public var lastDay: String?
    public var lastFamily: String?
    public var history: [FreshDayRecord]

    public init(enabled: Bool = false, lastDay: String? = nil, lastFamily: String? = nil, history: [FreshDayRecord] = []) {
        self.enabled = enabled
        self.lastDay = lastDay
        self.lastFamily = lastFamily
        self.history = history
    }
}

public struct FreshDayDecision: Equatable, Sendable {
    public let day: String
    public let family: String
}

/// Pure decision logic; the app calls it on launch, day change and wake (all triggers share one guard).
public enum FreshDayEngine {
    /// Today's pick if enabled and not yet applied today; never repeats the previous pick.
    public static func decide(now: Date, calendar: Calendar, state: FreshDayState, pool: [String]) -> FreshDayDecision? {
        guard state.enabled else { return nil }
        let today = FreshDay.dayKey(now, calendar: calendar)
        guard state.lastDay != today else { return nil }
        return FreshDay.pick(for: now, calendar: calendar, pool: pool, excluding: state.lastFamily)
            .map { FreshDayDecision(day: today, family: $0) }
    }

    /// Another pick for today, different from the current one. Salted by today's reroll count so it stays reproducible.
    public static func reroll(now: Date, calendar: Calendar, state: FreshDayState, pool: [String]) -> FreshDayDecision? {
        let today = FreshDay.dayKey(now, calendar: calendar)
        let salt = UInt64(state.history.filter { $0.day == today }.count)
        return FreshDay.pick(for: now, calendar: calendar, pool: pool, excluding: state.lastFamily, salt: salt)
            .map { FreshDayDecision(day: today, family: $0) }
    }

    public static func record(_ decision: FreshDayDecision, into state: inout FreshDayState) {
        state.lastDay = decision.day
        state.lastFamily = decision.family
        state.history.append(FreshDayRecord(day: decision.day, family: decision.family))
        if state.history.count > FreshDayState.historyLimit {
            state.history.removeFirst(state.history.count - FreshDayState.historyLimit)
        }
    }
}
