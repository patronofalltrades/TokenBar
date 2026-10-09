import Foundation

/// UserDefaults keys that more than one feature reads. Use them with `@AppStorage`.
/// One place for the names, so parallel tasks do not invent different keys.
enum SettingsKey {
    /// An `IndexChoice` raw value. Missing until the user picks an index in onboarding (DRD 2.5).
    static let index = "indexChoice"
    static let roastsEnabled = "roastsEnabled"          // default true
    static let alert95Enabled = "alert95Enabled"        // default true
    static let alertLimitEnabled = "alertLimitEnabled"  // default true
}

/// DRD 2.5, D41. TokenBar shows one index only.
enum IndexChoice: String, CaseIterable, Sendable {
    case cafe, tuition, water

    var title: String {
        switch self {
        case .cafe: "Café Index"
        case .tuition: "Tuition Meter"
        case .water: "Water Footprint"
        }
    }

    /// The saved choice. Moves a value of the old Funny/Serious setting one time:
    /// funny becomes café. Serious has no match, so onboarding asks again (D41). The old café index toggle goes too.
    static func saved(in defaults: UserDefaults = .standard) -> IndexChoice? {
        if let old = defaults.string(forKey: "barStyle") {
            if defaults.string(forKey: SettingsKey.index) == nil {
                defaults.set(old == "funny" ? "cafe" : nil, forKey: SettingsKey.index)
            }
            defaults.removeObject(forKey: "barStyle")
            defaults.removeObject(forKey: "cafeIndexEnabled")
        }
        return defaults.string(forKey: SettingsKey.index).flatMap(IndexChoice.init)
    }
}
