import AppKit
import Foundation
import Testing
@testable import TokenBar

private struct ReadError: Error {}

/// One model "m" at 1 USD per 1M input tokens and a rate of 1, so 1M input tokens cost €1.
private let prices = try! PriceTable.decode(Data(#"""
{"last_verified": "2026-10-08", "usd_to_eur": 1, "fx_updated": "2026-10-08", "fx_note": "n",
 "models": [{"id": "m", "input": 1, "source": "s", "last_verified": "2026-10-08"}]}
"""#.utf8))

private let madrid: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
}()

/// 2026-10-08 12:00 in Madrid, a Thursday.
private let noon = madrid.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!

private func record(_ provider: ProviderID = .claudeCode, eur: Double, at date: Date = noon.addingTimeInterval(-3600),
                    model: String = "m") -> UsageRecord {
    UsageRecord(provider: provider, model: model, timestamp: date, tokens: TokenCounts(input: Int(eur * 1_000_000)))
}

private func limit(_ percent: Double, resets: Date? = nil, name: String = "5-hour") -> LimitWindow {
    LimitWindow(name: name, usedPercent: percent, resetsAt: resets, observedAt: noon)
}

private func snapshot(_ records: [UsageRecord] = [], limits: [LimitWindow] = [], of provider: ProviderID = .claudeCode) -> ProviderSnapshot {
    ProviderSnapshot(provider: provider, records: records, limits: limits, updatedAt: noon)
}

private let codexMissing = CocoaError(.fileReadNoSuchFile)

/// A fresh `UserDefaults` suite for each test, so tests do not share settings or the café unit of the day.
private final class Fixture {
    let suite = "DisplayBuilderTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    var roasts: RoastSelector

    init(style: BarStyle? = .serious) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(style?.rawValue, forKey: SettingsKey.barStyle)
        roasts = RoastSelector(roasts: try! Roast.shipped(), randomIndex: { _ in 0 }, defaults: defaults)
    }

    deinit { defaults.removePersistentDomain(forName: suite) }

    func build(_ snapshots: [ProviderSnapshot], errors: [ProviderID: any Error] = [.codex: codexMissing],
               now: Date = noon) -> DisplaySnapshot {
        let builder = DisplayBuilder(prices: prices, cafe: try! CafeData.shipped(), defaults: defaults, calendar: madrid)
        return builder.build(snapshots: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) }),
                             errors: errors, lastRefresh: now, now: now, roasts: &roasts,
                             tuition: TuitionTotal(defaults: defaults, calendar: madrid))
    }
}

// MARK: - States

@Test func noProviderInstalledIsNoData() {
    let s = Fixture().build([], errors: [.claudeCode: ClaudeCodeProvider.Failure.notFound, .codex: codexMissing])
    #expect(s.state == .noData)
    #expect(s.menuBarSymbol == "circle.dashed" && s.menuBarText.isEmpty)
    #expect(s.rows.allSatisfy { !$0.installed && $0.errorText == nil })
    #expect(s.tuitionLine == nil && s.roast == nil)
}

@Test func installedProviderWithoutDataIsNoData() {
    let s = Fixture(style: .funny).build([snapshot()])
    #expect(s.state == .noData)
    #expect(s.rows.first { $0.provider == .claudeCode }?.installed == true)
}

@Test func errorOnlyWhenEveryInstalledProviderFails() {
    let failing = Fixture().build([snapshot(limits: [limit(50)])], errors: [.claudeCode: ReadError(), .codex: codexMissing])
    #expect(failing.state == .error)
    #expect(failing.menuBarSymbol == "exclamationmark.circle")
    #expect(failing.rows[0].errorText?.contains("Claude Code") == true)
    #expect(failing.rows[1].installed == false && failing.rows[1].errorText == nil)

    // One provider fails, one works: Normal, the error shows in the popover only (DRD 2.4 rule 2).
    let mixed = Fixture().build([snapshot(limits: [limit(40)], of: .codex)], errors: [.claudeCode: ReadError()])
    #expect(mixed.state == .normal)
    #expect(mixed.rows[0].errorText != nil && mixed.rows[1].errorText == nil)
}

@Test(arguments: [BarStyle.funny, .serious])
func warningShowsTheLimitInBothStyles(style: BarStyle) {
    let s = Fixture(style: style).build([snapshot([record(eur: 6.12)], limits: [limit(87.9)])])
    #expect(s.state == .warning)
    #expect(s.menuBarText == "87%" && s.menuBarSymbol == "exclamationmark.triangle.fill")
}

@Test(arguments: [BarStyle.funny, .serious])
func limitHitShowsTimeToReset(style: BarStyle) {
    let resets = noon.addingTimeInterval(108 * 60)
    let s = Fixture(style: style).build([snapshot([record(eur: 6.12)], limits: [limit(100, resets: resets), limit(30, name: "weekly")])])
    #expect(s.state == .limitHit)
    #expect(s.menuBarText == "1h48" && s.menuBarSymbol == "hourglass")
    #expect(MenuBarLabel.voiceOverLabel(s, now: noon) == "TokenBar. Claude Code limit reached. Resets in 1 hour, 48 minutes.")
}

@Test func passedResetShowsZero() {
    let s = Fixture().build([snapshot(limits: [limit(100, resets: noon.addingTimeInterval(-1))])])
    #expect(s.rows[0].limits[0].usedPercent == 0)
    #expect(s.state == .normal && s.menuBarText == "0%")
}

// MARK: - Auto metric and styles

@Test func autoMetricIsTheHighestLimit() {
    let s = Fixture().build([snapshot([record(eur: 3.4)], limits: [limit(30)]), snapshot(limits: [limit(62, name: "weekly")], of: .codex)],
                            errors: [:])
    #expect(s.menuBarText == "62%" && s.menuBarSymbol == "circle.lefthalf.filled")
    #expect(MenuBarLabel.voiceOverLabel(s, now: noon) == "TokenBar. Codex, 62 percent of weekly limit. Today, about 3.40 euros.")
}

@Test func autoMetricIsTodaysCostWithoutLimits() {
    let s = Fixture().build([snapshot([record(eur: 3.4)])])
    #expect(s.menuBarText == "€3.4")
    #expect(s.costTodayEUR == Decimal(string: "3.4"))
}

@Test func seriousHasNoJokes() {
    let s = Fixture().build([snapshot([record(eur: 6.12)], limits: [limit(62)])])
    #expect(s.barStyle == .serious)
    #expect(s.cafeLine == nil && s.cafeSymbol == nil && s.tuitionLine == nil && s.roast == nil)
    #expect(s.pricesVerified == "2026-10-08" && s.lastRefresh == noon)
}

@Test func noStyleYetShowsThePrimaryMetric() {
    let s = Fixture(style: nil).build([snapshot([record(eur: 6.12)], limits: [limit(62)])])
    #expect(s.barStyle == nil && s.menuBarText == "62%" && s.roast == nil)
}

@Test func funnyShowsTheCafeValue() {
    let s = Fixture(style: .funny).build([snapshot([record(eur: 6.12)], limits: [limit(62)])])
    #expect(s.menuBarText == "3.4" && s.menuBarSymbol == "cup.and.saucer.fill")
    #expect(s.cafeLine == "Today = 3.4 cafés con leche" && s.cafeSymbol == "cup.and.saucer.fill")
    #expect(s.tuitionLine?.hasSuffix("tuition, in tokens") == true)
    #expect(s.roast != nil)
    #expect(MenuBarLabel.voiceOverLabel(s, now: noon) == "TokenBar. Claude Code, 62 percent of 5-hour limit. Today, 3.4 cafés con leche.")
}

@Test func funnySettingsTurnJokesOff() {
    let f = Fixture(style: .funny)
    f.defaults.set(false, forKey: SettingsKey.cafeIndexEnabled)
    f.defaults.set(false, forKey: SettingsKey.roastsEnabled)
    let s = f.build([snapshot([record(eur: 6.12)], limits: [limit(62)])])
    #expect(s.menuBarText == "62%" && s.cafeLine == nil && s.tuitionLine == nil && s.roast == nil)
}

@Test func errorHasNoRoast() {
    let s = Fixture(style: .funny).build([snapshot([record(eur: 6.12)])], errors: [.claudeCode: ReadError(), .codex: codexMissing])
    #expect(s.state == .error && s.roast == nil)
}

@Test func cafeUnitStaysForTheDay() {
    let f = Fixture(style: .funny)
    #expect(f.build([snapshot([record(eur: 6.12)])]).menuBarText == "3.4")  // café con leche is closest to 3
    // A fresh pick for €10.50 is pa amb tomàquet (3.0). The café con leche stays while it is in range.
    #expect(f.build([snapshot([record(eur: 10.5)])]).cafeLine == "Today = 5.8 cafés con leche")
    let tomorrow = noon.addingTimeInterval(24 * 3600)
    let next = f.build([snapshot([record(eur: 10.5, at: tomorrow)])], now: tomorrow)
    #expect(next.cafeLine == "Today = 3.0 pa amb tomàquets" && next.cafeSymbol == "fork.knife")
}

// MARK: - Costs

@Test func costsForTodayAndWeek() {
    let records = [record(eur: 2), record(eur: 3, at: noon.addingTimeInterval(-3 * 24 * 3600)),
                   record(eur: 50, at: noon.addingTimeInterval(-8 * 24 * 3600))]
    let s = Fixture().build([snapshot(records), snapshot([record(.codex, eur: 1)], of: .codex)], errors: [:])
    #expect(s.costTodayEUR == 3 && s.costWeekEUR == 6)
    #expect(s.rows.map(\.costTodayEUR) == [2, 1])
    #expect(s.rows.allSatisfy { !$0.hasUnpricedModels })
}

@Test func unpricedModelIsFlagged() {
    let s = Fixture().build([snapshot([record(eur: 1, model: "unknown-model")])])
    #expect(s.rows[0].hasUnpricedModels)
    #expect(s.rows[0].costTodayEUR == 0)  // usage today, but no known price
    #expect(s.rows[1].costTodayEUR == nil)
}

@Test func shortFormats() {
    #expect([42, 108, 599, 1439, 3 * 1440].map { DisplayBuilder.shortDuration(Double($0) * 60) } == ["42m", "1h48", "9h59", "23h", "3d"])
    #expect(["3.4", "9.96", "12.4", "999.6", "4321"].map { DisplayBuilder.shortEUR(Decimal(string: $0)!) }
            == ["€3.4", "€10", "€12", "€1k", "€4k"])
}

// MARK: - Width

/// The longest text that each state can show, with its symbol (DRD 2.2: max 52 pt).
@Test func longestLabelsFit() throws {
    let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    let units = try CafeData.shipped().units
    let normal = "circle.lefthalf.filled"
    var labels: [(String, String)] = [
        ("", "circle.dashed"), ("", "exclamationmark.circle"),
        ("100%", "hourglass"), ("9h59", "hourglass"), ("23h", "hourglass"), ("59m", "hourglass"), ("99d", "hourglass"),
        ("99%", "exclamationmark.triangle.fill"),
        ("79%", normal), ("€9.9", normal), ("€999", normal), ("€99k", normal),
        ("0.5", units[0].symbol),  // only the cheapest unit goes below 0.5 (DRD 7.6 rule 5); the bar shows one decimal
        ("999", units.max { $0.priceEUR < $1.priceEUR }!.symbol),  // above the range: the most expensive unit
    ]
    labels += units.flatMap { [("9.9", $0.symbol), ("20", $0.symbol)] }
    for (text, symbol) in labels {
        let image = try #require(NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular)))
        let textWidth = text.isEmpty ? 0 : NSAttributedString(string: text, attributes: [.font: font]).size().width + MenuBarLabel.spacing
        #expect(image.size.width + textWidth <= MenuBarLabel.width, "\(symbol) \(text): \(image.size.width + textWidth) pt")
        #expect(MenuBarLabel.image(symbol: symbol, text: text).size.width == MenuBarLabel.width)
    }
}

@Test func barValueKeepsOneDecimalBelowOne() {
    #expect(DisplayBuilder.barValue("0.49") == "0.5")
    #expect(DisplayBuilder.barValue("0.04") == "0.1")
    #expect(DisplayBuilder.barValue("3.4") == "3.4")
    #expect(DisplayBuilder.barValue("12") == "12")
}
