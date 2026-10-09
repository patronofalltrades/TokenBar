import Foundation

/// Everything that the menu bar label and the popover show (DRD 2 and 3).
/// `DisplayBuilder` (TRD-T08) makes it from the store. The views only read it.
/// One shared shape, so the label and the popover always show the same numbers.
struct DisplaySnapshot: Equatable, Sendable {
    /// DRD 2.4. There is no stale state (D-simple-stale): quiet logs keep the last value.
    enum State: Equatable, Sendable { case normal, warning, limitHit, noData, error }

    struct Limit: Equatable, Sendable {
        let name: String            // "5-hour", "weekly"
        let usedPercent: Double     // 0...100. The builder shows 0 after `resetsAt` passed.
        let resetsAt: Date?
        let observedAt: Date        // shown as "as of 14:02" (DRD 3.2)
    }

    struct ProviderRow: Equatable, Sendable {
        let provider: ProviderID
        let installed: Bool         // false: the source folder does not exist. Not an error.
        let errorText: String?      // set only when TokenBar cannot read an existing source
        let limits: [Limit]
        let hasUnpricedModels: Bool // true: the cost of part of the usage is not counted
    }

    let state: State
    let index: IndexChoice?         // nil until the user picks an index (DRD 2.5)
    let menuBarText: String         // for example "3.4", "62%", "87%", "1h48"
    let menuBarSymbol: String       // SF Symbol name (DRD 2.4)
    let rows: [ProviderRow]
    // No EUR value in the snapshot (D42). The costs stay in `DisplayBuilder`. The indexes come from them.
    let indexLine: String?          // the headline of the selected index (DRD 3.1). Nil before the index choice or without data.
    let indexSymbol: String?        // SF Symbol for `indexLine`. IES-213 replaces it with a custom icon.
    var indexEmoji: String? = nil   // emoji for the share card text (DRD 7.7)
    var indexDetail: String? = nil  // small second line: the unit equivalent and the week, or the burn year (DRD 3.1)
    let roast: String?              // nil before the user picks an index, when roasts are off, or when none matches
    let lastRefresh: Date?
    let pricesVerified: String      // the `last_verified` date of prices.json
}
