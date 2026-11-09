import Foundation
import Testing
@testable import FontSwitcherCore

@Suite struct FreshDayTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    let pool = ["Berkeley Mono", "Zed Mono", "JetBrains Mono", "Geist Mono", "Sarasa Mono SC"]

    func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = cal.timeZone
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f.date(from: s)!
    }

    @Test func pickIsDeterministicPerLocalDay() {
        let a = FreshDay.pick(for: date("2026-11-06T08:00:00"), calendar: cal, pool: pool, excluding: nil)
        let b = FreshDay.pick(for: date("2026-11-06T23:59:00"), calendar: cal, pool: pool.reversed(), excluding: nil)
        #expect(a != nil)
        #expect(a == b)  // same local day, pool order irrelevant
    }

    @Test func picksVaryAcrossDays() {
        let picks = Set((1...28).compactMap { d in
            FreshDay.pick(for: date(String(format: "2026-02-%02dT12:00:00", d)), calendar: cal, pool: pool, excluding: nil)
        })
        #expect(picks.count >= 3)
    }

    @Test func neverReturnsExcludedWhenAlternativesExist() {
        for d in 1...28 {
            let day = date(String(format: "2026-02-%02dT12:00:00", d))
            let first = FreshDay.pick(for: day, calendar: cal, pool: pool, excluding: nil)!
            #expect(FreshDay.pick(for: day, calendar: cal, pool: pool, excluding: first) != first)
        }
        #expect(FreshDay.pick(for: Date(), calendar: cal, pool: ["Only"], excluding: "Only") == "Only")
        #expect(FreshDay.pick(for: Date(), calendar: cal, pool: [], excluding: nil) == nil)
    }

    @Test func nonGregorianSystemCalendarGivesSameDayAndPick() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = cal.timeZone
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = cal.timeZone
        let now = date("2026-11-06T09:00:00")
        #expect(FreshDay.dayKey(now, calendar: japanese) == "2026-11-06")
        #expect(FreshDay.dayKey(now, calendar: buddhist) == "2026-11-06")
        #expect(FreshDay.pick(for: now, calendar: japanese, pool: pool, excluding: nil)
            == FreshDay.pick(for: now, calendar: cal, pool: pool, excluding: nil))
    }

    @Test func poolPrefersFavoritesWhenAtLeastTwo() {
        #expect(FreshDay.pool(favorites: ["A", "B"], monospaced: ["C", "D"]) == ["A", "B"])
        #expect(FreshDay.pool(favorites: ["A"], monospaced: ["C", "D"]) == ["C", "D"])
    }

    @Test func engineRespectsEnabledAndOncePerDay() {
        var state = FreshDayState()
        let now = date("2026-11-06T09:00:00")
        #expect(FreshDayEngine.decide(now: now, calendar: cal, state: state, pool: pool) == nil)  // disabled by default

        state.enabled = true
        let d = FreshDayEngine.decide(now: now, calendar: cal, state: state, pool: pool)
        #expect(d?.day == "2026-11-06")
        FreshDayEngine.record(d!, into: &state)
        #expect(state.lastDay == "2026-11-06")
        #expect(FreshDayEngine.decide(now: date("2026-11-06T22:00:00"), calendar: cal, state: state, pool: pool) == nil)

        let tomorrow = FreshDayEngine.decide(now: date("2026-11-07T07:00:00"), calendar: cal, state: state, pool: pool)
        #expect(tomorrow != nil)
        #expect(tomorrow?.family != d?.family)  // never repeats yesterday
    }

    @Test func rerollPicksADifferentFamilyEachTime() {
        var state = FreshDayState(enabled: true)
        let now = date("2026-11-06T09:00:00")
        let first = FreshDayEngine.decide(now: now, calendar: cal, state: state, pool: pool)!
        FreshDayEngine.record(first, into: &state)
        var seen = [first.family]
        for _ in 0..<3 {
            let r = FreshDayEngine.reroll(now: now, calendar: cal, state: state, pool: pool)!
            #expect(r.family != state.lastFamily)
            FreshDayEngine.record(r, into: &state)
            seen.append(r.family)
        }
        #expect(state.history.count <= FreshDayState.historyLimit)
        #expect(state.lastDay == "2026-11-06")
    }
}

@Suite struct StateStoreTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fs-state-\(UUID().uuidString)/state.json")
    }

    @Test func missingFileGivesDefaults() {
        let s = StateStore(url: tempURL()).load()
        #expect(s == AppState())
        #expect(s.freshDay.enabled == false)
    }

    @Test func roundTrips() throws {
        let store = StateStore(url: tempURL())
        var s = AppState()
        s.profiles = [Profile(name: "Work", family: "Berkeley Mono", size: 14, overrides: [.ghostty: FontChoice(family: nil, size: 15)])]
        s.favorites = ["Zed Mono", "Berkeley Mono"]
        s.enabledTargets = [.vscode, .ghostty]
        s.freshDay = FreshDayState(enabled: true, lastDay: "2026-11-06", lastFamily: "Zed Mono")
        try store.save(s)
        #expect(store.load() == s)
    }

    @Test func toleratesMissingKeys() throws {
        let store = StateStore(url: tempURL())
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"favorites": ["A"]}"#.utf8).write(to: store.url)
        let s = store.load()
        #expect(s.favorites == ["A"])
        #expect(s.profiles.isEmpty)
    }

    @Test func corruptFileIsMovedAsideAndDefaultsReturned() throws {
        let store = StateStore(url: tempURL())
        let dir = store.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.url)
        #expect(store.load() == AppState())
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("state.corrupt-") })
        #expect(!names.contains("state.json"))
    }
}
