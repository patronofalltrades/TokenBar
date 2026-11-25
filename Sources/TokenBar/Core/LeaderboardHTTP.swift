import Foundation
import Security

/// The only code that uses `URLSession`, and the only one that touches the Keychain for the leaderboard.
/// It sends a request only to the host of the server address (TRD 17.1). It keeps no cookies and no cache.
enum LeaderboardHTTP {
    static let timeout: TimeInterval = 10  // TRD 17.4 rule 5

    /// A send function for `LeaderboardClient`. A request to any other host than `host` fails.
    static func send(host: String) -> LeaderboardSend {
        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = timeout
            c.timeoutIntervalForResource = timeout
            c.httpCookieStorage = nil
            c.urlCache = nil
            c.waitsForConnectivity = false
            return c
        }())
        return { request in
            guard request.url.scheme == "https", request.url.host() == host else { throw URLError(.badURL) }
            var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
            urlRequest.httpMethod = request.method
            urlRequest.httpBody = request.body
            for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            var headers: [String: String] = [:]
            for (name, value) in http.allHeaderFields {
                if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
            }
            return LeaderboardResponse(status: http.statusCode, headers: headers, body: data)
        }
    }

    /// The configured client, or nil when the server address is empty. Nil means the app never sends.
    static func client(config: LeaderboardConfig?) -> LeaderboardClient? {
        guard let url = config?.url, let host = url.host() else { return nil }
        return LeaderboardClient(base: url, send: send(host: host))
    }
}

/// The member token in the Keychain (AGENTS 5.6). It never goes to a file, a log or `UserDefaults`.
struct KeychainTokenStore: LeaderboardTokenStore {
    private let service = "TokenBar.leaderboard"
    private let account = "member-token"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func token() -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { $1 } as CFDictionary, &item)
        return status == errSecSuccess ? (item as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
    }

    func save(_ token: String) {
        clear()
        SecItemAdd(query.merging([kSecValueData as String: Data(token.utf8),
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { $1 } as CFDictionary, nil)
    }

    func clear() { SecItemDelete(query as CFDictionary) }
}
