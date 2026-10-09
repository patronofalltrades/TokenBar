import Foundation
import Testing
@testable import TokenBar

private let units = try! CafeData.shipped().units
private let tuition = try! CafeData.shipped().tuition

private func unit(_ id: String) -> CafeUnit { units.first { $0.id == id }! }
private func pick(_ cost: String, kept: String? = nil) -> String? {
    CafeIndex.pick(costEUR: Decimal(string: cost)!, units: units, keptID: kept)?.text
}

// MARK: - Data file

@Test func shippedFileHasTheV1UnitsAndTuition() throws {
    let data = try CafeData.shipped()
    #expect(data.units.map(\.id) == ["cafe_con_leche", "pa_amb_tomaquet", "bravas_bar_tomas", "menu_del_dia"])
    #expect(unit("cafe_con_leche").priceEUR == Decimal(string: "1.80"))
    #expect(data.units.allSatisfy { !$0.priceNote.isEmpty && !$0.source.isEmpty })
    #expect(data.tuition.id == "iese_mba_tuition")
    #expect(data.tuition.label == "MBA tuition")
    #expect(data.tuition.priceEUR > 0)
    let shown = data.units.flatMap { [$0.singular, $0.plural] } + [data.tuition.label]
    #expect(shown.allSatisfy { !$0.contains("IESE") })
    // D25: the school name is in the data file, not in the Swift code.
    #expect(data.pickerDescription == "How many cafés con leche at the IESE cafeteria your tokens cost today.")
}

private func json(unitPrice: String = "1.8", tuitionPrice: String = "1000", ids: [String] = ["a"],
                  dropping field: String? = nil) -> Data {
    let unitsJSON = ids.map { id in
        let fields = ["id": "\"\(id)\"", "singular": "\"x\"", "plural": "\"xs\"",
                      "emoji": "\"e\"", "price_eur": unitPrice, "price_note": "\"n\"",
                      "source": "\"src\"", "updated": "\"2026-10-08\""]
        return "{" + fields.filter { $0.key != field }.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ",") + "}"
    }
    let tuitionJSON = #"{"id": "t", "label": "MBA tuition", "price_eur": \#(tuitionPrice), "source": "s", "updated": "d"}"#
    return Data(#"{"picker_description": "p", "units": [\#(unitsJSON.joined(separator: ","))], "tuition": \#(tuitionJSON)}"#.utf8)
}

@Test func validFileDecodes() throws {
    #expect(try CafeData.decode(json()).units.count == 1)
}

@Test(arguments: ["id", "singular", "plural", "emoji", "price_eur", "price_note", "source", "updated"])
func missingFieldRejectsFile(field: String) {
    #expect(throws: DecodingError.self) { try CafeData.decode(json(dropping: field)) }
}

@Test func badPricesAndIDsRejectFile() {
    #expect(throws: CafeDataError.badPrice("a")) { try CafeData.decode(json(unitPrice: "0")) }
    #expect(throws: CafeDataError.badPrice("a")) { try CafeData.decode(json(unitPrice: "-1")) }
    #expect(throws: CafeDataError.badPrice("t")) { try CafeData.decode(json(tuitionPrice: "0")) }
    #expect(throws: CafeDataError.duplicateID("a")) { try CafeData.decode(json(ids: ["a", "a"])) }
    #expect(throws: CafeDataError.noUnits) { try CafeData.decode(json(ids: [])) }
}

// MARK: - Unit selection (DRD 7.6 rules 2–7)

@Test func selectsInRangeUnitClosestToThree() {
    // café 3.0, pa 1.5, bravas 0.9, menú 0.54
    #expect(pick("5.40") == "3.0 cafés con leche")
    // café 6.7, pa 3.4, bravas 2.0, menú 1.2
    #expect(pick("12") == "3.4 pa amb tomàquets")
}

@Test func keepsTheDaysUnitWhileInRange() {
    #expect(pick("12", kept: "cafe_con_leche") == "6.7 cafés con leche")
    // café 27.8 is out of range, so select again: menú 5.0 is closest to 3.
    #expect(pick("50", kept: "cafe_con_leche") == "5.0 menús del día")
}

@Test func belowRangeUsesCheapestUnitWithTwoDecimals() {
    #expect(pick("0.20") == "0.11 cafés con leche")
}

@Test func aboveRangeUsesMostExpensiveUnit() {
    #expect(pick("400") == "40 menús del día")
}

@Test func zeroCostShowsNoLine() {
    #expect(pick("0") == nil)
    #expect(pick("-1") == nil)
}

// MARK: - Formatting

@Test(arguments: [
    ("0", "0 cafés con leche"),
    ("0.12", "0.12 cafés con leche"),
    ("0.5", "0.5 cafés con leche"),
    ("1", "1.0 café con leche"),
    ("0.99", "1.0 café con leche"),
    ("1.04", "1.0 café con leche"),
    ("1.06", "1.1 cafés con leche"),
    ("9.94", "9.9 cafés con leche"),
    ("9.96", "10 cafés con leche"),
    ("12.5", "13 cafés con leche"),
])
func formatsValue(value: String, expected: String) {
    #expect(CafeIndex.format(Decimal(string: value)!, unit: unit("cafe_con_leche")).text == expected)
}

@Test func bravasPluralIsTheSameAsSingular() {
    #expect(CafeIndex.format(2, unit: unit("bravas_bar_tomas")).text == "2.0 Bar Tomàs patatas bravas")
}

// MARK: - Tuition benchmark

@Test func tuitionPercentAndLine() {
    let spend = tuition.priceEUR * Decimal(string: "0.0004")!
    #expect(CafeIndex.tuitionPercent(spendEUR: spend, tuition: tuition) == "0.04%")
    #expect(CafeIndex.tuitionLine(spendEUR: spend, tuition: tuition) == "0.04% of your MBA tuition, in tokens (since install)")
    #expect(CafeIndex.tuitionPercent(spendEUR: 0, tuition: tuition) == "0.00%")
}

/// €114,000 tuition. €100 a day for 10 days: €113,000 left = 1130 days ≈ 3.09 years.
@Test func burnLineCases() {
    func line(_ spend: String, days: Double) -> String? {
        CafeIndex.burnLine(spendEUR: Decimal(string: spend)!, days: days, tuition: tuition, year: 2026)
    }
    #expect(line("1000", days: 10) == "At this pace, you'll burn through it by the year 2029.")
    #expect(line("0.3", days: 10) == "At this pace, you'll burn through it by the year 12,430.")
    #expect(line("1000", days: 0.9) == nil)       // less than 1 day of data
    #expect(line("0", days: 30) == nil)           // zero spend
    #expect(line("0.01", days: 30) == "At this pace, you'll burn through it by the year 99,999+. Bring snacks.")
    #expect(line("114000", days: 30) == "Tuition fully burned. The tokens graduated before you did.")
}

/// A tiny value shows "<.01%" (D41: "<0.01%" does not fit 68 pt).
@Test func tuitionBarValueHasFiveCharactersMaximum() {
    let values = ["0", "0.000049", "0.00005", "0.0004", "0.09994", "0.1234", "0.99949", "1.234"].map {
        CafeIndex.tuitionBarValue(spendEUR: tuition.priceEUR * Decimal(string: $0)!, tuition: tuition)
    }
    #expect(values == ["<.01%", "<.01%", "0.01%", "0.04%", "9.99%", "12.3%", "99.9%", "123%"])
}

private struct Clock {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }()
    let defaults: UserDefaults
    let total: TuitionTotal
    let day0: Date

    init() {
        let suite = "TokenBarTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        day0 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        total = TuitionTotal(defaults: defaults, calendar: calendar)
    }

    func day(_ n: Int, hour: Int = 0) -> Date {
        calendar.date(byAdding: DateComponents(day: n, hour: hour), to: day0)!
    }
    func costs(_ days: ClosedRange<Int>, _ eur: Decimal) -> [Date: Decimal] {
        Dictionary(uniqueKeysWithValues: days.map { (day($0), eur) })
    }
}

@Test func runningTotalCountsCompleteDaysOnce() {
    let c = Clock()
    // First launch: earlier days are not counted.
    #expect(c.total.update(now: c.day(0, hour: 10), dailyCostsEUR: c.costs(-5...(-1), 100), todayEUR: 2) == 2)
    #expect(c.defaults.object(forKey: TuitionTotal.firstLaunchKey) as? Date == c.day(0, hour: 10))
    #expect(c.defaults.object(forKey: TuitionTotal.countedThroughKey) as? Date == c.day(-1))

    var daily = c.costs(-5...(-1), 100)
    daily[c.day(0)] = 2
    #expect(c.total.update(now: c.day(1, hour: 9), dailyCostsEUR: daily, todayEUR: 3) == 5)
    // A second refresh on the same day does not count day 0 again.
    #expect(c.total.update(now: c.day(1, hour: 12), dailyCostsEUR: daily, todayEUR: 4) == 6)
    #expect(c.defaults.string(forKey: TuitionTotal.spendKey) == "2")

    // Three days later: days 1 to 3 are added.
    daily.merge(c.costs(1...3, 1)) { $1 }
    #expect(c.total.update(now: c.day(4, hour: 8), dailyCostsEUR: daily, todayEUR: 0) == 5)
    #expect(c.defaults.object(forKey: TuitionTotal.countedThroughKey) as? Date == c.day(3))
}

@Test func runningTotalSkipsDaysOlderThan35Days() {
    let c = Clock()
    _ = c.total.update(now: c.day(0), dailyCostsEUR: [:], todayEUR: 0)
    // At day 50 the window starts at day 15. Day 10 is lost, day 20 counts.
    let daily = [c.day(10): Decimal(7), c.day(20): Decimal(11)]
    #expect(c.total.update(now: c.day(50), dailyCostsEUR: daily, todayEUR: 0) == 11)
}

@Test func runningTotalIgnoresAClockThatMovesBack() {
    let c = Clock()
    _ = c.total.update(now: c.day(0), dailyCostsEUR: [:], todayEUR: 0)
    _ = c.total.update(now: c.day(5), dailyCostsEUR: c.costs(0...4, 1), todayEUR: 0)
    #expect(c.total.update(now: c.day(2), dailyCostsEUR: c.costs(0...4, 1), todayEUR: 0) == 5)
    #expect(c.defaults.object(forKey: TuitionTotal.countedThroughKey) as? Date == c.day(4))
}

@Test func tuitionYearsNeedsSevenDays() {
    let c = Clock()
    #expect(c.total.years(now: c.day(0), dailyCostsEUR: [:], tuition: tuition) == nil)
    _ = c.total.update(now: c.day(0, hour: 10), dailyCostsEUR: [:], todayEUR: 0)
    let daily = c.costs(-10...40, 10)
    #expect(c.total.years(now: c.day(6), dailyCostsEUR: daily, tuition: tuition) == nil)
    // 114,000 / 10 per day / 365 = 31.2
    #expect(c.total.years(now: c.day(7), dailyCostsEUR: daily, tuition: tuition) == "31 years")
}

@Test func tuitionYearsUsesTheLast30Days() {
    let c = Clock()
    _ = c.total.update(now: c.day(0), dailyCostsEUR: [:], todayEUR: 0)
    var daily = c.costs(0...9, 1000)
    daily.merge(c.costs(10...39, 10)) { $1 }
    #expect(c.total.years(now: c.day(40), dailyCostsEUR: daily, tuition: tuition) == "31 years")
}

@Test func tuitionYearsSingularAndZeroSpend() {
    let c = Clock()
    _ = c.total.update(now: c.day(0), dailyCostsEUR: [:], todayEUR: 0)
    #expect(c.total.years(now: c.day(10), dailyCostsEUR: [:], tuition: tuition) == nil)
    let perDay = tuition.priceEUR / 365
    #expect(c.total.years(now: c.day(10), dailyCostsEUR: c.costs(0...9, perDay), tuition: tuition) == "1 year")
}
