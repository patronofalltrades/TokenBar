import Foundation
import Testing
@testable import TokenBar

/// SplitMix64. A seeded generator gives the same roast sequence in each run.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-10-07 is a Wednesday.
private func date(day: Int = 7, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func state(_ now: Date = date(14), percent: Double? = 50) -> RoastState {
    RoastState(now: now, calendar: utc, percent: percent, lastUsage: now.addingTimeInterval(-60), costEUR: 5)
}

private func roast(_ id: String, _ text: String = "x", _ category: Roast.Category = .career) -> Roast {
    Roast(id: id, text: text, category: category, locale: "en")
}

/// Runs a test with a fresh `UserDefaults` suite, so tests do not share the rotation history.
private func withSelector(_ roasts: [Roast], seed: UInt64 = 1, _ body: (inout RoastSelector) -> Void) {
    let name = "RoastsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    var random = SeededRandom(state: seed)
    var selector = RoastSelector(roasts: roasts, randomIndex: { Int.random(in: 0..<$0, using: &random) }, defaults: defaults)
    body(&selector)
}

@Test func shippedFileIsValid() throws {
    let roasts = try Roast.shipped()
    #expect(roasts.count == 30)
    #expect(Set(roasts.map(\.category)) == Set(Roast.Category.allCases))
    for r in roasts {
        #expect(r.text.count <= 140, "\(r.id) is longer than 140 characters")
        #expect(!r.text.localizedCaseInsensitiveContains("IESE"), "\(r.id) names the school")
        #expect(r.placeholders.allSatisfy(Roast.knownPlaceholders.contains), "\(r.id)")
        #expect(r.id.hasPrefix(r.category.rawValue + "-"), "\(r.id)")
        #expect(r.locale == "en")
    }
}

@Test func loadRejectsBadFiles() {
    let bad = [
        #"{"roasts":[{"id":"a","text":"{nope}","category":"career","locale":"en"}]}"#,
        #"{"roasts":[{"id":"a","text":"x","category":"career","locale":"en"},{"id":"a","text":"y","category":"career","locale":"en"}]}"#,
        #"{"roasts":[{"id":"a","text":"x","category":"career","hours":"05:00-01:00","locale":"en"}]}"#,
        #"{"roasts":[{"id":"a","text":"x","category":"spicy","locale":"en"}]}"#,
        #"{"roasts":[{"id":"a","text":"x","category":"career","min_percent":90,"max_percent":10,"locale":"en"}]}"#,
    ]
    for json in bad {
        #expect(throws: (any Error).self, "\(json)") { try Roast.load(Data(json.utf8)) }
    }
}

@Test func categoryTriggers() {
    func fires(_ c: Roast.Category, _ edit: (inout RoastState) -> Void) -> Bool {
        var s = state()
        edit(&s)
        return s.triggers(c)
    }
    #expect(fires(.zero) { $0.lastUsage = nil })
    #expect(fires(.zero) { $0.lastUsage = date(day: 6, 23) })
    #expect(!fires(.zero) { _ in })
    #expect(fires(.low) { $0.percent = 19 })
    #expect(fires(.low) { $0.costEUR = 0.5 })
    #expect(!fires(.low) { $0.percent = 19; $0.lastUsage = nil })
    #expect(fires(.mid) { $0.percent = 20 })
    #expect(!fires(.mid) { $0.percent = 80 })
    #expect(fires(.high) { $0.percent = 80 })
    #expect(!fires(.high) { $0.percent = 100 })
    #expect(fires(.limit) { $0.limitHit = true })
    #expect(!fires(.limit) { _ in })
    #expect(fires(.late) { $0.now = date(2); $0.lastUsage = date(1, 40) })
    #expect(!fires(.late) { $0.now = date(2); $0.lastUsage = date(1) })
    #expect(!fires(.late) { $0.now = date(5); $0.lastUsage = date(5) })
    #expect(fires(.weekday) { $0.now = date(day: 5, 9) })     // Monday 09:00
    #expect(!fires(.weekday) { $0.now = date(day: 5, 10) })   // Monday 10:00
    #expect(fires(.weekday) { $0.now = date(day: 9, 18) })    // Friday 18:00
    #expect(fires(.weekday) { $0.now = date(day: 11, 12) })   // Sunday
    #expect(!fires(.weekday) { _ in })                         // Wednesday
    #expect(fires(.spend) { $0.costEUR = 20.01 })
    #expect(!fires(.spend) { $0.costEUR = 20 })
    #expect(fires(.career) { _ in })
    #expect(fires(.tuition) { $0.daysOfData = 7 })
    #expect(!fires(.tuition) { $0.daysOfData = 6 })
    #expect(fires(.provider) { $0.providersToday = ["codex"] })
    #expect(!fires(.provider) { _ in })
}

@Test func optionalFilters() throws {
    let shipped = try Roast.shipped()
    let p1 = try #require(shipped.first { $0.id == "provider-01" })
    let p2 = try #require(shipped.first { $0.id == "provider-02" })
    var s = state()
    s.providersToday = ["codex"]
    #expect(p1.matches(s) && !p2.matches(s))
    s.providersToday = ["codex", "claudeCode"]
    #expect(!p1.matches(s) && p2.matches(s))

    var night = roast("n")
    night.hours = "00:00-05:00"
    night.weekdays = [.wed]
    night.minPercent = 80
    #expect(night.matches(state(date(4, 59), percent: 85)))
    #expect(!night.matches(state(date(5), percent: 85)))
    #expect(!night.matches(state(date(day: 8, 4), percent: 85)))  // Thursday
    #expect(!night.matches(state(date(4), percent: 79)))
    #expect(!night.matches(state(date(4), percent: nil)))
}

@Test func limitRoastsHavePriority() throws {
    let shipped = try Roast.shipped()
    var s = state(percent: 100)
    s.limitHit = true
    s.reset = "1h48"
    withSelector(shipped) { selector in
        for minute in stride(from: 0, to: 30, by: 11) {
            s.now = date(14, minute)
            let text = selector.roast(for: s)
            #expect(selector.history.last?.hasPrefix("limit-") == true, "\(text ?? "nil")")
        }
    }
}

@Test func noRepeatInLastTen() {
    let roasts = (1...12).map { roast("career-\($0)") }
    withSelector(roasts) { selector in
        for step in 0..<40 {
            let before = selector.history
            _ = selector.roast(for: state(date(day: 7, 0).addingTimeInterval(Double(step) * 11 * 60)))
            let picked = selector.history.last!
            #expect(!before.suffix(10).contains(picked))
            #expect(selector.history.count == min(step + 1, 10))
        }
    }
}

@Test func holdsForTenMinutesAndChangesOnStateChange() {
    let roasts = (1...5).map { roast("mid-\($0)", "mid \($0)", .mid) } + (1...5).map { roast("high-\($0)", "high \($0)", .high) }
    withSelector(roasts) { selector in
        let first = selector.roast(for: state(date(14)))
        #expect(first != nil)
        #expect(selector.roast(for: state(date(14, 9))) == first)
        let next = selector.roast(for: state(date(14, 10)))
        #expect(next != first && next?.hasPrefix("mid") == true)
        let warning = selector.roast(for: state(date(14, 11), percent: 85))
        #expect(warning?.hasPrefix("high") == true)
        #expect(selector.roast(for: state(date(14, 12), percent: 86)) == warning)
    }
}

@Test func keepsCurrentRoastWhenNoOtherMatches() {
    withSelector([roast("career-1", "only one")]) { selector in
        #expect(selector.roast(for: state(date(14))) == "only one")
        #expect(selector.roast(for: state(date(15))) == "only one")
        #expect(selector.roast(for: state(date(16), percent: 90)) == "only one")
    }
    withSelector([roast("mid-1", "mid", .mid)]) { selector in
        #expect(selector.roast(for: state(percent: 90)) == nil)
    }
}

@Test func rendersPlaceholders() {
    let text = "{percent}% used, {remaining}% left of {model} at {time}. Cost {cost}, {unit_value} {unit_plural}."
    var s = state(date(23, 5), percent: 87.9)
    s.model = "Opus"
    s.costEUR = 3.4
    s.unitValue = "1.9"
    s.unitPlural = "cafés con leche"
    withSelector([roast("career-1", text)]) { selector in
        #expect(selector.roast(for: s) == "87% used, 13% left of Opus at 23:05. Cost ≈ €3.40, 1.9 cafés con leche.")
    }
    s.model = nil
    withSelector([roast("career-1", text)]) { selector in
        #expect(selector.roast(for: s) == nil)
    }
    withSelector([roast("tuition-1", "{tuition_years}", .tuition)]) { selector in
        var t = state()
        t.daysOfData = 7
        #expect(selector.roast(for: t) == nil)
        t.tuitionYears = "412 years"
        #expect(selector.roast(for: t) == "412 years")
    }
}

@Test func seededRandomIsDeterministic() throws {
    let shipped = try Roast.shipped()
    func run(seed: UInt64) -> [String?] {
        var out: [String?] = []
        withSelector(shipped, seed: seed) { selector in
            for step in 0..<10 {
                out.append(selector.roast(for: state(date(14).addingTimeInterval(Double(step) * 11 * 60))))
            }
        }
        return out
    }
    #expect(run(seed: 42) == run(seed: 42))
    #expect(run(seed: 42) != run(seed: 7))
}
