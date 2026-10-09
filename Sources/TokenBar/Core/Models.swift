import Foundation

/// Raw values are stored in data files and settings. Do not change them.
enum ProviderID: String, Codable, Sendable, CaseIterable {
    case claudeCode, codex
}

/// All values are token counts.
struct TokenCounts: Hashable, Sendable {
    var input = 0          // uncached input
    var output = 0         // includes reasoning or thinking tokens
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
}

/// One API response, or one API bucket.
struct UsageRecord: Hashable, Sendable {
    let provider: ProviderID
    let model: String
    let timestamp: Date
    let tokens: TokenCounts
}

struct LimitWindow: Sendable {
    let name: String           // "5-hour", "weekly"
    let usedPercent: Double    // 0...100
    let resetsAt: Date?
    let observedAt: Date       // shown as "as of 14:02" (DRD 3.2)
}

struct ProviderSnapshot: Sendable {
    let provider: ProviderID
    let records: [UsageRecord] // window: last 35 days
    let limits: [LimitWindow]
    let updatedAt: Date
}
