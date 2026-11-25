import Foundation

/// Decides when the app talks to the leaderboard server (TRD 17.4). It sends nothing when the leaderboard is off,
/// not set up, or without a server address. It has no UI and no network framework, so tests run it with a fake network.
actor LeaderboardEngine {
    struct State: Equatable, Sendable {
        var members: [LeaderboardMember] = []
        var updatedAt: Date?
        /// A short text for Settings. Nil when all is well. The popover card ignores it (DRD 3.10).
        var problem: String?
    }

    static let submitGap: TimeInterval = 30 * 60
    static let fetchGap: TimeInterval = 5 * 60
    static let maxBackoff: TimeInterval = 2 * 3600

    private let client: LeaderboardClient?
    private let tokens: any LeaderboardTokenStore
    private(set) var state = State()
    private var account = LeaderboardAccount()
    private var lastSubmit: Date?
    private var lastFetch: Date?
    private var blockedUntil: Date?
    private var failures = 0
    /// A problem that waiting does not fix (taken handle, full class). The engine stops until the user changes the account.
    private var halted = false

    /// A nil `client` means no server address: the engine never sends.
    init(client: LeaderboardClient?, tokens: any LeaderboardTokenStore) {
        self.client = client
        self.tokens = tokens
    }

    /// Call after each refresh. `numbers` is nil when the app has no usage data yet.
    @discardableResult
    func tick(account new: LeaderboardAccount, numbers: LeaderboardNumbers?, now: Date) async -> State {
        guard new.enabled, new.isValid, let client else {
            reset(to: new)
            return state
        }
        if new != account { reset(to: new) }
        guard !halted, blockedUntil.map({ now >= $0 }) ?? true else { return state }

        var token = tokens.token()
        if token == nil, numbers != nil {
            token = LeaderboardRules.makeToken()
            tokens.save(token!)
        }
        if let numbers, let token, lastSubmit.map({ now.timeIntervalSince($0) >= Self.submitGap }) ?? true {
            let outcome = await client.submit(code: new.code, handle: new.handle, token: token, numbers: numbers,
                                              asOf: LeaderboardRules.dateString(now))
            guard handle(outcome, now: now) else { return state }
            lastSubmit = now
            lastFetch = nil  // show the own number at once
        }
        if lastFetch.map({ now.timeIntervalSince($0) >= Self.fetchGap }) ?? true {
            let (outcome, members) = await client.board(code: new.code)
            guard handle(outcome, now: now) else { return state }
            lastFetch = now
            state.members = members
            state.updatedAt = now
        }
        return state
    }

    /// "Leave class and delete my data". The token goes only when the server accepted, or when the server has no such member.
    /// With no server address or no token, there is nothing on a server, so the local data goes.
    func leave(account: LeaderboardAccount) async -> Bool {
        defer { reset(to: LeaderboardAccount()) }
        guard let client, let token = tokens.token(), account.isValid else {
            tokens.clear()
            return true
        }
        let outcome = await client.delete(code: account.code, handle: account.handle, token: token)
        switch outcome {
        case .ok, .notFound:
            tokens.clear()
            return true
        default:
            return false
        }
    }

    private func reset(to new: LeaderboardAccount) {
        account = new
        state = State()
        lastSubmit = nil
        lastFetch = nil
        blockedUntil = nil
        failures = 0
        halted = false
    }

    /// Returns true when the request worked.
    private func handle(_ outcome: LeaderboardClient.Outcome, now: Date) -> Bool {
        switch outcome {
        case .ok:
            failures = 0
            state.problem = nil
            return true
        case .handleTaken, .unauthorized:
            stop("This handle is in use by another Mac. Pick another handle.")
        case .classFull:
            stop("This class is full.")
        case .tooSoon(let retryAfter):
            blockedUntil = now.addingTimeInterval(min(max(retryAfter, 60), Self.maxBackoff))
        case .invalid, .notFound, .failed:
            // A quiet failure. Each next failure doubles the wait (TRD 17.4 rule 3).
            failures += 1
            blockedUntil = now.addingTimeInterval(min(Self.maxBackoff, Self.fetchGap * pow(2, Double(min(failures, 10) - 1))))
        }
        return false
    }

    private func stop(_ problem: String) {
        halted = true
        state.problem = problem
    }
}
