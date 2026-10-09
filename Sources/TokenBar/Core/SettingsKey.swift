import Foundation

/// UserDefaults keys that more than one feature reads. Use them with `@AppStorage`.
/// One place for the names, so parallel tasks do not invent different keys.
enum SettingsKey {
    /// A `BarStyle` raw value. Missing until the user picks a style in onboarding (DRD 2.5).
    static let barStyle = "barStyle"
    static let roastsEnabled = "roastsEnabled"          // default true
    static let cafeIndexEnabled = "cafeIndexEnabled"    // default true
    static let alert95Enabled = "alert95Enabled"        // default true
    static let alertLimitEnabled = "alertLimitEnabled"  // default true
}

/// DRD 2.5. Serious turns off roasts and the café index.
enum BarStyle: String, CaseIterable, Sendable {
    case funny, serious
}
