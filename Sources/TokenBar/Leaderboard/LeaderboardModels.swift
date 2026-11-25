import Foundation

/// The three numbers that the app sends to the class leaderboard (TRD 17.1). No other usage data leaves the Mac.
struct LeaderboardNumbers: Equatable, Sendable {
    var weekCostEUR: Double
    var weekOutputTokens: Int
    var spendSinceInstallEUR: Double
}

/// One member on the board, as the server returns it (TRD 17.2).
struct LeaderboardMember: Codable, Equatable, Sendable {
    let handle: String
    let asOf: String
    let weekCostEUR: Double
    let weekOutputTokens: Int
    let spendSinceInstallEUR: Double
}

/// What the user typed in Settings (DRD 5.1).
struct LeaderboardAccount: Equatable, Sendable {
    var enabled = false
    var code = ""
    var handle = ""

    init(enabled: Bool = false, code: String = "", handle: String = "") {
        self.enabled = enabled
        self.code = code
        self.handle = handle
    }

    init(_ defaults: UserDefaults) {
        self.init(enabled: defaults.bool(forKey: SettingsKey.leaderboardEnabled),
                  code: defaults.string(forKey: SettingsKey.leaderboardCode) ?? "",
                  handle: defaults.string(forKey: SettingsKey.leaderboardHandle) ?? "")
    }

    var isValid: Bool { LeaderboardRules.isValidCode(code) && LeaderboardRules.isValidHandle(handle) }
}

/// `Resources/leaderboard.json`. The `endpoint` is empty until the maintainer deploys the server (D62).
struct LeaderboardConfig: Decodable, Sendable {
    let endpoint: String

    /// The server address, or nil if it is empty or not an https address. A leaderboard request needs this.
    var url: URL? {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https", let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    static func shipped() throws -> LeaderboardConfig {
        guard let url = Bundle.tokenBar.url(forResource: "leaderboard", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(LeaderboardConfig.self, from: Data(contentsOf: url))
    }
}

/// The rules of the protocol (TRD 17.2). The server checks the same rules.
enum LeaderboardRules {
    static func isValidCode(_ code: String) -> Bool { code.wholeMatch(of: /[a-z0-9-]{8,40}/) != nil }
    static func isValidHandle(_ handle: String) -> Bool { handle.wholeMatch(of: /[A-Za-z0-9_-]{2,20}/) != nil }

    /// A random class code, for example "cafe-k3m9-x7q2". The alphabet has no 0, 1, i, l or o.
    static func makeCode() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        func part() -> String { String((0..<4).map { _ in alphabet.randomElement()! }) }
        return "cafe-\(part())-\(part())"
    }

    /// The member token: 32 random bytes in base64url, 43 characters (TRD 17.1).
    static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// "2026-11-25", in the calendar of the user.
    static func dateString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Where the member token lives. The app uses the Keychain (AGENTS 5.6). Tests use memory.
protocol LeaderboardTokenStore: Sendable {
    func token() -> String?
    func save(_ token: String)
    func clear()
}
