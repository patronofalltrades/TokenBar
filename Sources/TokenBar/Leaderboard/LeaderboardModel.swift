import Foundation
import Observation

/// What the popover card shows (DRD 3.10). No EUR (D42).
struct LeaderboardCardData: Equatable, Sendable {
    let code: String
    let index: IndexChoice
    let entries: [LeaderboardRanking.Entry]  // all members, best first
    let updatedAt: Date

    var me: LeaderboardRanking.Entry? { entries.first(where: \.isMe) }
    var top: ArraySlice<LeaderboardRanking.Entry> { entries.prefix(3) }

    var headline: String? {
        me.map { "You are #\($0.rank) of \(entries.count)" }
    }

    var voiceOver: String {
        let places = ["First", "Second", "Third"]
        let list = zip(places, top).map { "\($0): \($1.handle), \($1.text)" }.joined(separator: ". ")
        return ["Class leaderboard", me.map { "You are number \($0.rank) of \(entries.count)" }, list]
            .compactMap { $0 }.joined(separator: ". ")
    }
}

/// The leaderboard state for the views (Settings and popover). The engine decides when to send.
@MainActor @Observable
final class LeaderboardModel {
    /// False when `Resources/leaderboard.json` has no server address. Settings then says "not set up" (DRD 5.1).
    let isConfigured: Bool
    private(set) var state = LeaderboardEngine.State()
    private(set) var leaveFailed = false

    @ObservationIgnored private let engine: LeaderboardEngine
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var busy = false

    init(client: LeaderboardClient?, tokens: any LeaderboardTokenStore, defaults: UserDefaults = .standard) {
        isConfigured = client != nil
        engine = LeaderboardEngine(client: client, tokens: tokens)
        self.defaults = defaults
    }

    /// One tick at a time: a second call while one runs is dropped. The next refresh calls again.
    func tick(numbers: LeaderboardNumbers?, now: Date = Date()) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        state = await engine.tick(account: LeaderboardAccount(defaults), numbers: numbers, now: now)
    }

    /// "Leave class and delete my data" (DRD 5.1). The settings clear only when the server accepted.
    func leave() async {
        busy = true
        defer { busy = false }
        let ok = await engine.leave(account: LeaderboardAccount(defaults))
        leaveFailed = !ok
        guard ok else { return }
        defaults.set(false, forKey: SettingsKey.leaderboardEnabled)
        defaults.removeObject(forKey: SettingsKey.leaderboardCode)
        defaults.removeObject(forKey: SettingsKey.leaderboardHandle)
        state = LeaderboardEngine.State()
    }

    /// The card, or nil: the leaderboard is off, no board is loaded, or the user has no index (DRD 3.10).
    func card(index: IndexChoice?, cafe: CafeData, water: WaterData) -> LeaderboardCardData? {
        let account = LeaderboardAccount(defaults)
        guard account.enabled, account.isValid, let index, let updatedAt = state.updatedAt, !state.members.isEmpty else { return nil }
        return LeaderboardCardData(
            code: account.code, index: index,
            entries: LeaderboardRanking.entries(state.members, index: index, me: account.handle, cafe: cafe, water: water),
            updatedAt: updatedAt)
    }
}
