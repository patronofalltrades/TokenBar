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
        let costTodayEUR: Decimal?  // nil: no usage today
        let hasUnpricedModels: Bool // true: show "price unknown" for part of the usage
    }

    let state: State
    let barStyle: BarStyle?         // nil until the user picks a style (DRD 2.5)
    let menuBarText: String         // for example "3.4", "62%", "87%", "1h48"
    let menuBarSymbol: String       // SF Symbol name (DRD 2.4)
    let rows: [ProviderRow]
    let costTodayEUR: Decimal
    let costWeekEUR: Decimal
    let cafeLine: String?           // nil in Serious, or when the café index is off
    let cafeSymbol: String?         // SF Symbol of the café unit in `cafeLine`
    let tuitionLine: String?        // nil in Serious, or before there is data
    let roast: String?              // nil in Serious, when roasts are off, or when none matches
    let lastRefresh: Date?
    let pricesVerified: String      // the `last_verified` date of prices.json
}
