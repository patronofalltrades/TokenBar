import Foundation

/// One roast from `roasts.json` (DRD 7.2).
struct Roast: Codable, Equatable, Sendable {
    enum Category: String, Codable, Sendable, CaseIterable {
        case zero, low, mid, high, limit, late, weekday, spend, career, tuition, provider, water
    }

    /// The order agrees with `Calendar` weekday numbers 1...7.
    enum Weekday: String, Codable, Sendable, CaseIterable { case sun, mon, tue, wed, thu, fri, sat }

    static let knownPlaceholders: Set<String> = [
        "percent", "remaining", "model", "provider", "reset", "time",
        "cost", "unit_value", "unit_plural", "tuition_percent", "tuition_years", "water",
    ]

    let id: String
    let text: String
    let category: Category
    var minPercent: Double?
    var maxPercent: Double?
    var hours: String?          // local time, "HH:MM-HH:MM", end can be "24:00"
    var weekdays: [Weekday]?
    var provider: String?       // ProviderID raw value, for example "codex"
    let locale: String

    var placeholders: [String] { text.matches(of: /\{([a-z_]+)\}/).map { String($0.1) } }

    /// Converts "HH:MM-HH:MM" to minutes since midnight. Returns nil for a bad range.
    static func minutes(_ hours: String) -> Range<Int>? {
        let p = hours.split(whereSeparator: { $0 == "-" || $0 == ":" }).compactMap { Int($0) }
        guard p.count == 4, p[1] < 60, p[3] < 60 else { return nil }
        let start = p[0] * 60 + p[1], end = p[2] * 60 + p[3]
        return start < end && end <= 24 * 60 ? start..<end : nil
    }

    struct InvalidFile: Error, CustomStringConvertible { let description: String }

    /// Decodes and validates a roast file. Rejects the whole file on the first error (TRD 9).
    static func load(_ data: Data) throws -> [Roast] {
        struct File: Decodable { let roasts: [Roast] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let roasts = try decoder.decode(File.self, from: data).roasts
        var ids = Set<String>()
        for r in roasts {
            guard ids.insert(r.id).inserted else { throw InvalidFile(description: "\(r.id): duplicate id") }
            guard !r.text.isEmpty, !r.locale.isEmpty else { throw InvalidFile(description: "\(r.id): empty text or locale") }
            if let bad = r.placeholders.first(where: { !knownPlaceholders.contains($0) }) {
                throw InvalidFile(description: "\(r.id): unknown placeholder {\(bad)}")
            }
            if let h = r.hours, minutes(h) == nil { throw InvalidFile(description: "\(r.id): bad hours \(h)") }
            if let lo = r.minPercent, let hi = r.maxPercent, lo > hi {
                throw InvalidFile(description: "\(r.id): min_percent > max_percent")
            }
        }
        return roasts
    }

    static func shipped() throws -> [Roast] {
        guard let url = Bundle.tokenBar.url(forResource: "roasts", withExtension: "json") else {
            throw InvalidFile(description: "roasts.json is not in the bundle")
        }
        return try load(Data(contentsOf: url))
    }

    /// Optional filters from the data file. The category trigger is in `RoastState.triggers`.
    func matches(_ s: RoastState) -> Bool {
        if let lo = minPercent { guard let p = s.percent, p >= lo else { return false } }
        if let hi = maxPercent { guard let p = s.percent, p <= hi else { return false } }
        if let hours, let range = Roast.minutes(hours), !range.contains(s.minuteOfDay) { return false }
        if let weekdays, !weekdays.contains(s.weekday) { return false }
        // A provider roast names the only provider used today. Without a name, it needs two or more providers.
        if let provider { return s.providersToday == [provider] }
        return category != .provider || s.providersToday.count > 1
    }
}

/// The current state for roast selection. The caller formats the display-only values.
struct RoastState {
    var now: Date
    var calendar = Calendar.current
    var percent: Double?                // primary limit, 0...100
    var limitHit = false
    var lastUsage: Date?
    var costEUR: Double?                // cost today
    var providersToday: Set<String> = []  // ProviderID raw values
    var daysOfData = 0
    var model: String?
    var provider: String?               // display name
    var reset: String?                  // for example "1h48"
    var unitValue: String?
    var unitPlural: String?
    var tuitionPercent: String?         // for example "0.04%"
    var tuitionYears: String?           // for example "412 years"; nil with less than 7 days of data
    var water: String?                  // for example "22 L"; set only for the Water Footprint

    var minuteOfDay: Int {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return c.hour! * 60 + c.minute!
    }

    var weekday: Roast.Weekday { Roast.Weekday.allCases[calendar.component(.weekday, from: now) - 1] }

    var usedToday: Bool { lastUsage.map { calendar.isDate($0, inSameDayAs: now) } ?? false }

    /// Category triggers (DRD 7.3).
    func triggers(_ category: Roast.Category) -> Bool {
        let hour = minuteOfDay / 60
        switch category {
        case .zero: return !usedToday
        case .low: return usedToday && ((percent ?? 100) < 20 || (costEUR ?? 1) < 1)
        case .mid: return (20..<80).contains(percent ?? -1)
        case .high: return (80..<100).contains(percent ?? -1)
        case .limit: return limitHit
        case .late: return hour < 5 && lastUsage.map { now.timeIntervalSince($0) <= 30 * 60 } ?? false
        case .weekday:
            switch weekday {
            case .mon: return hour < 10
            case .fri: return hour >= 18
            case .sat, .sun: return true
            default: return false
            }
        case .spend: return (costEUR ?? 0) > 20
        case .career: return true
        case .tuition: return daysOfData >= 7
        case .provider: return !providersToday.isEmpty
        case .water: return water != nil
        }
    }

    var placeholderValues: [String: String] {
        let used = percent.map { Int($0) }  // truncate, so 99.6% shows as 99%, not as a hit limit
        let values: [String: String?] = [
            "percent": used.map(String.init),
            "remaining": used.map { String(100 - $0) },
            "model": model,
            "provider": provider,
            "reset": reset,
            "time": String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60),
            // "cost" has no value: no EUR in the UI (D42). A roast with `{cost}` does not show.
            "unit_value": unitValue,
            "unit_plural": unitPlural,
            "tuition_percent": tuitionPercent,
            "tuition_years": tuitionYears,
            "water": water,
        ]
        return values.compactMapValues { $0 }
    }
}

/// Selects one roast for the current state (DRD 7.3 and 7.4).
struct RoastSelector {
    let roasts: [Roast]
    /// Returns a random index in `0..<count`. Tests inject a seeded source.
    let randomIndex: (_ count: Int) -> Int
    let defaults: UserDefaults
    private var lastChange: Date?
    private var lastCategories: Set<Roast.Category> = []

    init(roasts: [Roast], randomIndex: @escaping (Int) -> Int = { .random(in: 0..<$0) }, defaults: UserDefaults = .standard) {
        self.roasts = roasts
        self.randomIndex = randomIndex
        self.defaults = defaults
    }

    /// The last 10 roast IDs shown, oldest first. Local only (DRD 7.4, rule 5).
    var history: [String] {
        get { defaults.stringArray(forKey: "roastHistory") ?? [] }
        nonmutating set { defaults.set(Array(newValue.suffix(10)), forKey: "roastHistory") }
    }

    /// Returns the rendered roast, or nil when no roast is available (DRD 7.4, rule 4).
    mutating func roast(for state: RoastState) -> String? {
        let values = state.placeholderValues
        let categories = Set(Roast.Category.allCases.filter(state.triggers))
        var eligible = roasts.filter {
            categories.contains($0.category) && $0.matches(state) && $0.placeholders.allSatisfy { values[$0] != nil }
        }
        if eligible.contains(where: { $0.category == .limit }) { eligible.removeAll { $0.category != .limit } }

        let history = history
        let current = eligible.first { $0.id == history.last }
        let hold = current != nil && categories == lastCategories
            && lastChange.map { state.now.timeIntervalSince($0) < 10 * 60 } ?? false
        let fresh = eligible.filter { !history.contains($0.id) }
        if !hold, !fresh.isEmpty {
            let next = fresh[randomIndex(fresh.count)]
            self.history = history + [next.id]
            lastChange = state.now
            lastCategories = categories
            return render(next, values)
        }
        // Hold the current roast. Also keep it when every other match is in the history.
        return current.map { render($0, values) }
    }

    private func render(_ roast: Roast, _ values: [String: String]) -> String {
        values.reduce(roast.text) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }
}
