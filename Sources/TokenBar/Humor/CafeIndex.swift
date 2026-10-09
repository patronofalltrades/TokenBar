import Foundation

/// One café-index unit (DRD 7.6).
struct CafeUnit: Decodable, Sendable {
    let id, singular, plural, symbol, emoji: String
    let priceEUR: Decimal
    let priceNote, source, updated: String

    enum CodingKeys: String, CodingKey {
        case id, singular, plural, symbol, emoji, source, updated
        case priceEUR = "price_eur", priceNote = "price_note"
    }
}

/// The tuition benchmark. It is not a café unit (DRD 7.6).
struct Tuition: Decodable, Sendable {
    let id, label: String
    let priceEUR: Decimal
    let source, updated: String

    enum CodingKeys: String, CodingKey {
        case id, label, source, updated
        case priceEUR = "price_eur"
    }
}

enum CafeDataError: Error, Equatable {
    case noUnits
    case duplicateID(String)
    case badPrice(String)
}

/// The contents of `cafe-units.json` (TRD 9).
struct CafeData: Decodable, Sendable {
    /// The Café Index text in onboarding step 2. It can name the school, because it is data (D25).
    let pickerDescription: String
    let units: [CafeUnit]
    let tuition: Tuition

    enum CodingKeys: String, CodingKey {
        case units, tuition
        case pickerDescription = "picker_description"
    }

    /// Decodes and validates the file. Any error rejects the whole file.
    static func decode(_ json: Data) throws -> CafeData {
        let data = try JSONDecoder().decode(CafeData.self, from: json)
        guard !data.units.isEmpty else { throw CafeDataError.noUnits }
        var seen: Set<String> = [data.tuition.id]
        for unit in data.units {
            guard seen.insert(unit.id).inserted else { throw CafeDataError.duplicateID(unit.id) }
            guard unit.priceEUR > 0 else { throw CafeDataError.badPrice(unit.id) }
        }
        guard data.tuition.priceEUR > 0 else { throw CafeDataError.badPrice(data.tuition.id) }
        return data
    }

    static func shipped() throws -> CafeData {
        guard let url = Bundle.tokenBar.url(forResource: "cafe-units", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }
}

enum CafeIndex {
    struct Pick: Sendable {
        let unit: CafeUnit
        /// The display value, for example "3.4". Fills `{unit_value}`.
        let value: String
        /// `singular` or `plural`, for the display value. Fills `{unit_plural}`.
        let name: String
        /// For example "3.4 cafés con leche".
        var text: String { "\(value) \(name)" }
    }

    /// Selects one unit for a cost (DRD 7.6 rules 2–7). Returns nil for a cost of 0.
    /// `keptID` is the unit that the caller picked earlier today. It stays while it is in range (rule 4).
    static func pick(costEUR: Decimal, units: [CafeUnit], keptID: String? = nil) -> Pick? {
        guard costEUR > 0, !units.isEmpty else { return nil }
        let valued = units.map { (unit: $0, value: costEUR / $0.priceEUR) }
        let inRange = valued.filter { $0.value >= 0.5 && $0.value <= 20 }
        let chosen = inRange.first { $0.unit.id == keptID }
            ?? inRange.min { abs($0.value - 3) < abs($1.value - 3) }
            ?? (valued.allSatisfy { $0.value < 0.5 }
                ? valued.min { $0.unit.priceEUR < $1.unit.priceEUR }!
                : valued.max { $0.unit.priceEUR < $1.unit.priceEUR }!)
        return format(chosen.value, unit: chosen.unit)
    }

    /// "0" at 0. Two decimals below 0.5, one decimal below 10, none at 10 and above.
    static func format(_ value: Decimal, unit: CafeUnit) -> Pick {
        if value == 0 { return Pick(unit: unit, value: "0", name: unit.plural) }
        var places = value < 0.5 ? 2 : 1
        var shown = rounded(value, places)
        if places == 1, shown >= 10 {
            places = 0
            shown = rounded(value, 0)
        }
        return Pick(unit: unit, value: fixed(shown, places), name: shown == 1 ? unit.singular : unit.plural)
    }

    /// `{tuition_percent}`, for example "0.04%".
    static func tuitionPercent(spendEUR: Decimal, tuition: Tuition) -> String {
        fixed(rounded(spendEUR / tuition.priceEUR * 100, 2), 2) + "%"
    }

    /// The menu bar value of the Tuition Meter. Fits 68 pt (D41): "0.04%", "12.3%", "123%".
    /// Below 0.005% it shows "<.01%". "<0.01%" does not fit.
    static func tuitionBarValue(spendEUR: Decimal, tuition: Tuition) -> String {
        let percent = spendEUR / tuition.priceEUR * 100
        guard percent >= Decimal(string: "0.005")! else { return "<.01%" }
        let places = percent < Decimal(string: "9.995")! ? 2 : percent < Decimal(string: "99.95")! ? 1 : 0
        return fixed(rounded(percent, places), places) + "%"
    }

    /// The popover line of the Tuition Meter (DRD 7.6 rule 1).
    static func tuitionLine(spendEUR: Decimal, tuition: Tuition) -> String {
        "\(tuitionPercent(spendEUR: spendEUR, tuition: tuition)) of your \(tuition.label), in tokens (since install)"
    }

    /// The second Tuition Meter line (D41): the year when the spend since install reaches tuition, at the
    /// average daily spend since install. Nil below 1 day of data or at zero spend.
    static func burnLine(spendEUR: Decimal, days: Double, tuition: Tuition, year: Int) -> String? {
        guard days >= 1, spendEUR > 0 else { return nil }
        guard spendEUR < tuition.priceEUR else { return "Tuition fully burned. The tokens graduated before you did." }
        let spend = NSDecimalNumber(decimal: spendEUR).doubleValue
        let remaining = NSDecimalNumber(decimal: tuition.priceEUR).doubleValue - spend
        let target = Double(year) + (remaining / (spend / days) / 365.25).rounded()
        guard target <= 99_999 else { return "At this pace, you'll burn through it by the year 99,999+. Bring snacks." }
        // A separator only from 5 digits: "2031", "12,345". "2,031" looks odd.
        let shown = Int(target).formatted(.number.grouping(target >= 10_000 ? .automatic : .never).locale(Locale(identifier: "en_US")))
        return "At this pace, you'll burn through it by the year \(shown)."
    }

    /// Formats a rounded value with a fixed number of decimals and a "." separator.
    private static func fixed(_ value: Decimal, _ places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }

    static func rounded(_ value: Decimal, _ places: Int) -> Decimal {
        var input = value, result = Decimal()
        NSDecimalRound(&result, &input, places, .plain)
        return result
    }
}

/// The tuition running total in `UserDefaults` (TRD 9, rules 5–7).
/// The total is in EUR, because the cost engine returns EUR (D17).
struct TuitionTotal {
    static let firstLaunchKey = "tuitionFirstLaunch"
    static let spendKey = "tuitionSpendEUR"
    static let countedThroughKey = "tuitionCountedThrough"

    let defaults: UserDefaults
    var calendar = Calendar.current

    /// Adds each complete day that is not counted yet, then returns the spend since first launch.
    /// `dailyCostsEUR` has one entry for each day, keyed by `calendar.startOfDay(for:)`.
    func update(now: Date, dailyCostsEUR: [Date: Decimal], todayEUR: Decimal) -> Decimal {
        let today = calendar.startOfDay(for: now)
        let yesterday = day(-1, from: today)
        var spend = Decimal(string: defaults.string(forKey: Self.spendKey) ?? "") ?? 0

        let counted = defaults.object(forKey: Self.countedThroughKey) as? Date
        if let counted {
            // A day older than the 35-day window is not counted (rule 7).
            var next = max(day(1, from: counted), day(-35, from: today))
            while next < today {
                spend += dailyCostsEUR[next] ?? 0
                next = day(1, from: next)
            }
        } else {
            // First launch: count from today only.
            defaults.set(now, forKey: Self.firstLaunchKey)
        }
        defaults.set("\(spend)", forKey: Self.spendKey)
        // Do not move the date back if the clock moves back.
        if counted.map({ $0 < yesterday }) ?? true {
            defaults.set(yesterday, forKey: Self.countedThroughKey)
        }
        return spend + todayEUR
    }

    /// `{tuition_years}`, for example "412 years". The average uses the complete days since
    /// first launch, maximum the last 30. Returns nil below 7 days (DRD 7.6 rule 4) or at zero spend.
    func years(now: Date, dailyCostsEUR: [Date: Decimal], tuition: Tuition) -> String? {
        guard let first = defaults.object(forKey: Self.firstLaunchKey) as? Date else { return nil }
        let today = calendar.startOfDay(for: now)
        let start = max(calendar.startOfDay(for: first), day(-30, from: today))
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        guard days >= 7 else { return nil }
        let total = (0..<days).reduce(Decimal(0)) { $0 + (dailyCostsEUR[day($1, from: start)] ?? 0) }
        guard total > 0 else { return nil }
        let years = CafeIndex.rounded(tuition.priceEUR / (total / Decimal(days)) / 365, 0)
        return years == 1 ? "1 year" : "\(years) years"
    }

    private func day(_ offset: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: date)!
    }
}
