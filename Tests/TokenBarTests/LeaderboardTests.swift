import Foundation
import Testing
@testable import TokenBar

/// A fake network. It records each request and answers with the next status in `replies`, then 204.
private actor FakeNetwork {
    private(set) var requests: [LeaderboardRequest] = []
    var replies: [Int] = []
    var board = #"{"v":1,"members":[]}"#

    func handle(_ request: LeaderboardRequest) -> LeaderboardResponse {
        requests.append(request)
        let status = replies.isEmpty ? (request.method == "GET" ? 200 : 204) : replies.removeFirst()
        return LeaderboardResponse(status: status, body: request.method == "GET" ? Data(board.utf8) : Data())
    }

    func setReplies(_ r: [Int]) { replies = r }
    func setBoard(_ b: String) { board = b }
    func methods() -> [String] { requests.map(\.method) }
}

private final class MemoryTokens: LeaderboardTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func token() -> String? { lock.withLock { value } }
    func save(_ token: String) { lock.withLock { value = token } }
    func clear() { lock.withLock { value = nil } }
}

private let base = URL(string: "https://board.example.com")!
private let account = LeaderboardAccount(enabled: true, code: "cafe-k3m9-x7q2", handle: "ana")
private let numbers = LeaderboardNumbers(weekCostEUR: 8.5, weekOutputTokens: 123_456, spendSinceInstallEUR: 45.6)
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func engine(_ net: FakeNetwork, tokens: MemoryTokens = MemoryTokens()) -> LeaderboardEngine {
    LeaderboardEngine(client: LeaderboardClient(base: base, send: { await net.handle($0) }), tokens: tokens)
}

@Suite struct LeaderboardRulesTests {
    @Test func codeAndHandleRules() {
        #expect(LeaderboardRules.isValidCode("cafe-k3m9-x7q2"))
        #expect(!LeaderboardRules.isValidCode("short"))
        #expect(!LeaderboardRules.isValidCode("Has-Capitals-123"))
        #expect(!LeaderboardRules.isValidCode(String(repeating: "a", count: 41)))
        #expect(!LeaderboardRules.isValidCode("cafe-k3m9-x7q2\n"))
        #expect(LeaderboardRules.isValidHandle("Ana_B-1"))
        #expect(!LeaderboardRules.isValidHandle("a"))
        #expect(!LeaderboardRules.isValidHandle("has space"))
        #expect(!LeaderboardRules.isValidHandle("../x"))
        #expect(!LeaderboardRules.isValidHandle(String(repeating: "a", count: 21)))
    }

    @Test func madeCodeAndTokenAreValid() {
        for _ in 0..<50 { #expect(LeaderboardRules.isValidCode(LeaderboardRules.makeCode())) }
        let token = LeaderboardRules.makeToken()
        #expect(token.count == 43)
        #expect(token.wholeMatch(of: /[A-Za-z0-9_-]{43}/) != nil)
        #expect(token != LeaderboardRules.makeToken())
    }

    @Test func configNeedsHttps() throws {
        func config(_ endpoint: String) throws -> LeaderboardConfig {
            try JSONDecoder().decode(LeaderboardConfig.self, from: Data(#"{"endpoint":"\#(endpoint)"}"#.utf8))
        }
        #expect(try config("").url == nil)
        #expect(try config("http://board.example.com").url == nil)
        #expect(try config("https://board.example.com").url != nil)
    }

    @Test func dateString() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        #expect(LeaderboardRules.dateString(Date(timeIntervalSince1970: 1_795_000_000), calendar: calendar) == "2026-11-18")
    }
}

@Suite struct LeaderboardEngineTests {
    @Test func sendsNothingWhenOffOrNotSetUp() async {
        let net = FakeNetwork()
        let e = engine(net)
        var off = account; off.enabled = false
        var badCode = account; badCode.code = "x"
        var badHandle = account; badHandle.handle = "a b"
        for a in [off, badCode, badHandle, LeaderboardAccount()] { await e.tick(account: a, numbers: numbers, now: t0) }
        // No server address: no client, so no request is possible.
        let none = LeaderboardEngine(client: nil, tokens: MemoryTokens())
        await none.tick(account: account, numbers: numbers, now: t0)
        #expect(await net.requests.isEmpty)
        #expect(await none.state == LeaderboardEngine.State())
    }

    @Test func sendsExactlyTheDocumentedFields() async throws {
        let net = FakeNetwork()
        let tokens = MemoryTokens()
        await engine(net, tokens: tokens).tick(account: account, numbers: numbers, now: t0)
        let put = try #require(await net.requests.first)
        #expect(put.method == "PUT")
        #expect(put.url.absoluteString == "https://board.example.com/v1/classes/cafe-k3m9-x7q2/members/ana")
        let token = try #require(tokens.token())
        #expect(put.headers["authorization"] == "Bearer \(token)")
        let data = try #require(put.body)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(body.keys) == ["v", "asOf", "weekCostEUR", "weekOutputTokens", "spendSinceInstallEUR"])
        #expect(body["v"] as? Int == 1)
        #expect(body["weekOutputTokens"] as? Int == 123_456)
        #expect(body["weekCostEUR"] as? Double == 8.5)
        #expect((body["asOf"] as? String)?.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
        #expect(data.count <= 1024)
        // The GET has no token and no body.
        let get = try #require(await net.requests.last)
        #expect(get.method == "GET" && get.body == nil && get.headers["authorization"] == nil)
    }

    @Test func clampsNumbersToTheServerLimits() async throws {
        let net = FakeNetwork()
        let hostile = LeaderboardNumbers(weekCostEUR: .infinity, weekOutputTokens: Int.max, spendSinceInstallEUR: -5)
        await engine(net).tick(account: account, numbers: hostile, now: t0)
        let data = try #require(await net.requests.first?.body)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["weekCostEUR"] as? Double == 0)
        #expect(body["weekOutputTokens"] as? Int == 10_000_000_000_000)
        #expect(body["spendSinceInstallEUR"] as? Double == 0)
    }

    @Test func intervals() async {
        let net = FakeNetwork()
        let e = engine(net)
        await e.tick(account: account, numbers: numbers, now: t0)
        #expect(await net.methods() == ["PUT", "GET"])
        await e.tick(account: account, numbers: numbers, now: t0.addingTimeInterval(4 * 60))
        #expect(await net.methods() == ["PUT", "GET"])  // too early for both
        await e.tick(account: account, numbers: numbers, now: t0.addingTimeInterval(6 * 60))
        #expect(await net.methods() == ["PUT", "GET", "GET"])  // board only
        await e.tick(account: account, numbers: numbers, now: t0.addingTimeInterval(31 * 60))
        #expect(await net.methods() == ["PUT", "GET", "GET", "PUT", "GET"])
    }

    @Test func noNumbersMeansNoSend() async {
        let net = FakeNetwork()
        await engine(net).tick(account: account, numbers: nil, now: t0)
        #expect(await net.methods() == ["GET"])
    }

    @Test func backoffDoublesAndStops() async {
        let net = FakeNetwork()
        await net.setReplies(Array(repeating: 500, count: 60))
        let e = engine(net)
        await e.tick(account: account, numbers: numbers, now: t0)
        #expect(await net.requests.count == 1)
        // Probe each minute. The tick that sends a request is the next attempt. Its time gives the wait.
        var last = t0
        var waits: [TimeInterval] = []
        var minute = 0
        while waits.count < 8, minute < 2000 {
            minute += 1
            let now = t0.addingTimeInterval(Double(minute) * 60)
            let before = await net.requests.count
            await e.tick(account: account, numbers: numbers, now: now)
            if await net.requests.count > before {
                waits.append(now.timeIntervalSince(last))
                last = now
            }
        }
        #expect(waits.count == 8)
        // Dates have a small rounding error, so compare with a tolerance of one second.
        func near(_ a: TimeInterval, _ b: TimeInterval) -> Bool { abs(a - b) < 1 }
        #expect(near(waits[0], 5 * 60) && near(waits[1], 10 * 60) && near(waits[2], 20 * 60))
        #expect(waits.allSatisfy { $0 <= 2 * 3600 + 1 })
        #expect(near(waits[7], 2 * 3600))
    }

    @Test func takenHandleStopsUntilTheAccountChanges() async {
        let net = FakeNetwork()
        await net.setReplies([409])
        let e = engine(net)
        let state = await e.tick(account: account, numbers: numbers, now: t0)
        #expect(state.problem != nil)
        await e.tick(account: account, numbers: numbers, now: t0.addingTimeInterval(24 * 3600))
        #expect(await net.requests.count == 1)  // halted, even a day later
        var other = account; other.handle = "ana2"
        let next = await e.tick(account: other, numbers: numbers, now: t0.addingTimeInterval(24 * 3600))
        #expect(next.problem == nil)
        #expect(await net.requests.count == 3)
    }

    @Test func tooSoonWaitsForRetryAfter() async {
        let net = FakeNetwork()
        let client = LeaderboardClient(base: base, send: { request in
            let reply = await net.handle(request)
            return reply.status == 429 ? LeaderboardResponse(status: 429, headers: ["retry-after": "900"]) : reply
        })
        await net.setReplies([429])
        let e = LeaderboardEngine(client: client, tokens: MemoryTokens())
        await e.tick(account: account, numbers: numbers, now: t0)
        await e.tick(account: account, numbers: numbers, now: t0.addingTimeInterval(600))
        #expect(await net.requests.count == 1)
        await e.tick(account: account, numbers: numbers, now: t0.addingTimeInterval(901))
        #expect(await net.requests.count == 3)
    }

    @Test func thrownNetworkErrorIsQuiet() async {
        struct Down: Error {}
        let e = LeaderboardEngine(client: LeaderboardClient(base: base, send: { _ in throw Down() }), tokens: MemoryTokens())
        let state = await e.tick(account: account, numbers: numbers, now: t0)
        #expect(state.members.isEmpty && state.problem == nil)
    }

    @Test func boardIsKept() async throws {
        let net = FakeNetwork()
        await net.setBoard(#"{"v":1,"members":[{"handle":"ana","asOf":"2026-11-25","weekCostEUR":8.5,"weekOutputTokens":10,"spendSinceInstallEUR":1}]}"#)
        let state = await engine(net).tick(account: account, numbers: numbers, now: t0)
        #expect(state.members.map(\.handle) == ["ana"])
        #expect(state.updatedAt == t0)
    }

    @Test func leaveDeletesThenClearsTheToken() async {
        let net = FakeNetwork()
        let tokens = MemoryTokens()
        let e = engine(net, tokens: tokens)
        await e.tick(account: account, numbers: numbers, now: t0)
        #expect(tokens.token() != nil)
        await net.setReplies([500])
        #expect(await e.leave(account: account) == false)
        #expect(tokens.token() != nil)  // the server did not accept: keep the token to try again
        #expect(await e.leave(account: account) == true)
        #expect(tokens.token() == nil)
        #expect(await net.methods().filter { $0 == "DELETE" }.count == 2)
    }

    @Test func leaveWithoutServerClearsLocally() async {
        let tokens = MemoryTokens()
        tokens.save("x")
        let none = LeaderboardEngine(client: nil, tokens: tokens)
        #expect(await none.leave(account: account))
        #expect(tokens.token() == nil)
    }

    @Test func clientRefusesPlainHttpAndBadNames() async {
        let net = FakeNetwork()
        let http = LeaderboardClient(base: URL(string: "http://board.example.com")!, send: { await net.handle($0) })
        #expect(await http.submit(code: "cafe-k3m9-x7q2", handle: "ana", token: "t", numbers: numbers, asOf: "2026-11-25") == .invalid)
        let https = LeaderboardClient(base: base, send: { await net.handle($0) })
        #expect(await https.submit(code: "cafe-k3m9-x7q2", handle: "../x", token: "t", numbers: numbers, asOf: "2026-11-25") == .invalid)
        #expect(await https.board(code: "no").0 == .invalid)
        #expect(await net.requests.isEmpty)
    }
}

@Suite struct LeaderboardRankingTests {
    private func member(_ handle: String, cost: Double = 0, output: Int = 0, spend: Double = 0) -> LeaderboardMember {
        .init(handle: handle, asOf: "2026-11-25", weekCostEUR: cost, weekOutputTokens: output, spendSinceInstallEUR: spend)
    }

    @Test func eachBoardUsesItsOwnNumber() throws {
        let cafe = try CafeData.shipped(), water = try WaterData.shipped()
        let members = [member("ana", cost: 1, output: 900, spend: 5), member("bob", cost: 9, output: 100, spend: 1),
                       member("cy", cost: 5, output: 500, spend: 9)]
        func order(_ i: IndexChoice) -> [String] {
            LeaderboardRanking.entries(members, index: i, me: "CY", cafe: cafe, water: water).map(\.handle)
        }
        #expect(order(.cafe) == ["bob", "cy", "ana"])
        #expect(order(.water) == ["ana", "cy", "bob"])
        #expect(order(.tuition) == ["cy", "ana", "bob"])
        let entries = LeaderboardRanking.entries(members, index: .cafe, me: "CY", cafe: cafe, water: water)
        #expect(entries.map(\.rank) == [1, 2, 3])
        #expect(entries.first(where: \.isMe)?.handle == "cy")  // handles match without case
    }

    @Test func tiesRankByHandleAndNoCurrencyText() throws {
        let cafe = try CafeData.shipped(), water = try WaterData.shipped()
        let members = [member("zed", cost: 3), member("amy", cost: 3), member("bob", cost: 3)]
        for index in IndexChoice.allCases {
            let entries = LeaderboardRanking.entries(members, index: index, me: "x", cafe: cafe, water: water)
            #expect(entries.map(\.handle) == ["amy", "bob", "zed"])
            for entry in entries {
                for banned in ["€", "EUR", "euro"] { #expect(!entry.text.localizedCaseInsensitiveContains(banned)) }
            }
        }
    }

    @Test func hostileNumbersDoNotTrap() throws {
        let cafe = try CafeData.shipped(), water = try WaterData.shipped()
        let members = [member("a1", cost: 1e300, output: Int.max, spend: 1e300), member("b1", cost: -5, output: -1, spend: -1),
                       member("c1", cost: .nan), member("d1", cost: .infinity)]
        for index in IndexChoice.allCases {
            _ = LeaderboardRanking.entries(members, index: index, me: "a1", cafe: cafe, water: water)
        }
    }
}

@Suite struct LeaderboardNumbersTests {
    /// The three numbers come from the same data as the popover: cost and output of the last 7 days, and the spend since install.
    @Test func builderGivesTheThreeNumbers() throws {
        let suite = "LbNumbers.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prices = try PriceTable.decode(Data(#"""
            {"last_verified": "2026-10-08", "usd_to_eur": 1, "fx_updated": "2026-10-08", "fx_note": "n",
             "models": [{"id": "m", "input": 1, "source": "s", "last_verified": "2026-10-08"}]}
            """#.utf8))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [UsageRecord(provider: .claudeCode, model: "m", timestamp: now.addingTimeInterval(-60),
                                   tokens: TokenCounts(input: 25_000_000, output: 10_000)),
                       // Older than 7 days: not in the week numbers.
                       UsageRecord(provider: .claudeCode, model: "m", timestamp: now.addingTimeInterval(-10 * 86_400),
                                   tokens: TokenCounts(input: 1_000_000, output: 500))]
        var roasts = RoastSelector(roasts: try Roast.shipped(), randomIndex: { _ in 0 }, defaults: defaults)
        let snapshot = DisplayBuilder(prices: prices, cafe: try CafeData.shipped(), water: try WaterData.shipped(), defaults: defaults)
            .build(snapshots: [.claudeCode: ProviderSnapshot(provider: .claudeCode, records: records, limits: [], updatedAt: now)],
                   errors: [:], lastRefresh: now, now: now, roasts: &roasts, tuition: TuitionTotal(defaults: defaults))
        let numbers = try #require(snapshot.leaderboard)
        #expect(abs(numbers.weekCostEUR - 25) < 0.001)
        #expect(numbers.weekOutputTokens == 10_000)
        #expect(abs(numbers.spendSinceInstallEUR - 25) < 0.001)
    }

    @Test func noDataMeansNoNumbers() throws {
        let suite = "LbNumbers.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var roasts = RoastSelector(roasts: try Roast.shipped(), randomIndex: { _ in 0 }, defaults: defaults)
        let snapshot = DisplayBuilder(prices: try .shipped(), cafe: try CafeData.shipped(), water: try WaterData.shipped(), defaults: defaults)
            .build(snapshots: [:], errors: [:], lastRefresh: nil, now: Date(), roasts: &roasts, tuition: TuitionTotal(defaults: defaults))
        #expect(snapshot.leaderboard == nil)
    }
}
