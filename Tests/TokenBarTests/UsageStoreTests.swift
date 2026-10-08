import Foundation
import Testing
@testable import TokenBar

private struct ReadError: Error {}

private actor StubProvider: UsageProvider {
    nonisolated let id: ProviderID
    private var records: [UsageRecord] = []
    private var fails = false
    private(set) var calls = 0

    init(_ id: ProviderID) { self.id = id }

    func set(records: [UsageRecord] = [], fails: Bool = false) {
        self.records = records
        self.fails = fails
    }

    func fetch(now: Date) async throws -> ProviderSnapshot {
        calls += 1
        if fails { throw ReadError() }
        let limit = LimitWindow(name: "5-hour", usedPercent: 40, resetsAt: nil, observedAt: now)
        return ProviderSnapshot(provider: id, records: records, limits: [limit], updatedAt: now)
    }
}

// 2026-10-08 12:00 in Madrid (UTC+2).
private let noon = Date(timeIntervalSince1970: 1_791_453_600)

private var madrid: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
}

private func record(_ provider: ProviderID, _ model: String, at date: Date, input: Int) -> UsageRecord {
    UsageRecord(provider: provider, model: model, timestamp: date, tokens: TokenCounts(input: input, output: 1))
}

@MainActor private func makeStore(_ providers: [StubProvider]) -> UsageStore {
    UsageStore(providers: providers, calendar: madrid, now: { noon })
}

@MainActor @Test func refreshMergesSnapshotsOfAllProviders() async {
    let claude = StubProvider(.claudeCode), codex = StubProvider(.codex)
    await claude.set(records: [record(.claudeCode, "opus", at: noon, input: 10)])
    await codex.set(records: [record(.codex, "gpt", at: noon, input: 20)])
    let store = makeStore([claude, codex])

    await store.refresh()

    #expect(store.snapshots.count == 2)
    #expect(store.snapshots[.claudeCode]?.limits.first?.usedPercent == 40)
    #expect(store.errors.isEmpty)
    #expect(store.lastRefresh == noon)
    #expect(store.isRefreshing == false)
}

@MainActor @Test func failedProviderKeepsLastSnapshotAndOthersUpdate() async {
    let claude = StubProvider(.claudeCode), codex = StubProvider(.codex)
    await claude.set(records: [record(.claudeCode, "opus", at: noon, input: 10)])
    let store = makeStore([claude, codex])
    await store.refresh()

    await claude.set(fails: true)
    await codex.set(records: [record(.codex, "gpt", at: noon, input: 20)])
    await store.refresh()

    #expect(store.snapshots[.claudeCode]?.records.count == 1)
    #expect(store.errors[.claudeCode] is ReadError)
    #expect(store.errors[.codex] == nil)
    #expect(store.snapshots[.codex]?.records.count == 1)

    await claude.set()
    await store.refresh()
    #expect(store.errors[.claudeCode] == nil)
    #expect(store.snapshots[.claudeCode]?.records.isEmpty == true)
}

@MainActor @Test func refreshReadsProvidersEachTime() async {
    let claude = StubProvider(.claudeCode)
    let store = makeStore([claude])
    await store.refresh()
    await store.refresh()
    #expect(await claude.calls == 2)
}

@MainActor @Test func todayStartsAtLocalMidnight() async {
    let claude = StubProvider(.claudeCode)
    let midnight = madrid.startOfDay(for: noon)
    await claude.set(records: [
        record(.claudeCode, "opus", at: midnight, input: 1),
        record(.claudeCode, "opus", at: midnight.addingTimeInterval(-1), input: 100),
        record(.claudeCode, "opus", at: noon, input: 2),
        record(.claudeCode, "sonnet", at: noon, input: 5),
    ])
    let store = makeStore([claude])
    await store.refresh()

    let today = store.totals(.today)[.claudeCode]
    #expect(today?["opus"] == TokenCounts(input: 3, output: 2))
    #expect(today?["sonnet"] == TokenCounts(input: 5, output: 1))
}

@MainActor @Test func weekIsRollingSevenDays() async {
    let claude = StubProvider(.claudeCode), codex = StubProvider(.codex)
    let weekStart = noon.addingTimeInterval(-7 * 24 * 3600)
    await claude.set(records: [
        record(.claudeCode, "opus", at: weekStart, input: 1),
        record(.claudeCode, "opus", at: weekStart.addingTimeInterval(-1), input: 100),
        record(.claudeCode, "opus", at: noon, input: 2),
    ])
    await codex.set(records: [record(.codex, "gpt", at: noon, input: 7)])
    let store = makeStore([claude, codex])
    await store.refresh()

    let week = store.totals(.week)
    #expect(week[.claudeCode]?["opus"] == TokenCounts(input: 3, output: 2))
    #expect(week[.codex]?["gpt"] == TokenCounts(input: 7, output: 1))
}
