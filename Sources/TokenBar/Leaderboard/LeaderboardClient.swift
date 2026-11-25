import Foundation

/// A request and a reply as plain values, so the client has no network framework and a test can replace the network.
struct LeaderboardRequest: Sendable {
    var method: String
    var url: URL
    var headers: [String: String] = [:]
    var body: Data?
}

struct LeaderboardResponse: Sendable {
    var status: Int
    var headers: [String: String] = [:]  // names in lower case
    var body = Data()
}

typealias LeaderboardSend = @Sendable (LeaderboardRequest) async throws -> LeaderboardResponse

/// The three requests of the protocol (TRD 17.2). The client sends nothing when a rule is broken.
struct LeaderboardClient: Sendable {
    enum Outcome: Equatable, Sendable {
        case ok, handleTaken, classFull, notFound, unauthorized, invalid
        case tooSoon(retryAfter: TimeInterval)
        case failed
    }

    let base: URL
    let send: LeaderboardSend

    private struct Body: Encodable {
        let v = 1
        let asOf: String
        let weekCostEUR: Double
        let weekOutputTokens: Int
        let spendSinceInstallEUR: Double
    }

    func submit(code: String, handle: String, token: String, numbers: LeaderboardNumbers, asOf: String) async -> Outcome {
        guard let url = member(code, handle) else { return .invalid }
        // The server limits (TRD 17.2). A number that is out of range would give 422 and the user would not see a rank.
        func limit(_ x: Double, _ max: Double) -> Double { x.isFinite ? min(Swift.max(x, 0), max) : 0 }
        let body = Body(asOf: asOf,
                        weekCostEUR: (limit(numbers.weekCostEUR, 100_000) * 100).rounded() / 100,
                        weekOutputTokens: min(Swift.max(numbers.weekOutputTokens, 0), 10_000_000_000_000),
                        spendSinceInstallEUR: (limit(numbers.spendSinceInstallEUR, 10_000_000) * 100).rounded() / 100)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(body) else { return .invalid }
        return await outcome(LeaderboardRequest(method: "PUT", url: url, headers: auth(token), body: data))
    }

    func board(code: String) async -> (Outcome, [LeaderboardMember]) {
        guard LeaderboardRules.isValidCode(code) else { return (.invalid, []) }
        let url = base.appending(path: "v1/classes/\(code)/board")
        guard let reply = try? await send(LeaderboardRequest(method: "GET", url: url)) else { return (.failed, []) }
        let result = Self.outcome(reply)
        guard result == .ok else { return (result, []) }
        struct Board: Decodable { let members: [LeaderboardMember] }
        guard let board = try? JSONDecoder().decode(Board.self, from: reply.body) else { return (.failed, []) }
        return (.ok, board.members)
    }

    func delete(code: String, handle: String, token: String) async -> Outcome {
        guard let url = member(code, handle) else { return .invalid }
        return await outcome(LeaderboardRequest(method: "DELETE", url: url, headers: auth(token)))
    }

    private func member(_ code: String, _ handle: String) -> URL? {
        guard base.scheme == "https", LeaderboardRules.isValidCode(code), LeaderboardRules.isValidHandle(handle) else { return nil }
        return base.appending(path: "v1/classes/\(code)/members/\(handle)")
    }

    private func auth(_ token: String) -> [String: String] { ["authorization": "Bearer \(token)", "content-type": "application/json"] }

    private func outcome(_ request: LeaderboardRequest) async -> Outcome {
        guard let reply = try? await send(request) else { return .failed }
        return Self.outcome(reply)
    }

    static func outcome(_ reply: LeaderboardResponse) -> Outcome {
        switch reply.status {
        case 200...204: .ok
        case 401: .unauthorized
        case 403: .classFull
        case 404: .notFound
        case 409: .handleTaken
        case 422: .invalid
        case 429: .tooSoon(retryAfter: reply.headers["retry-after"].flatMap(TimeInterval.init) ?? 600)
        default: .failed
        }
    }
}
