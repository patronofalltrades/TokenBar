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
                    model: String = "m", output: Int = 0) -> UsageRecord {
    UsageRecord(provider: provider, model: model, timestamp: date, tokens: TokenCounts(input: Int(eur * 1_000_000), output: output))
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

    init(index: IndexChoice? = nil) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(index?.rawValue, forKey: SettingsKey.index)
        roasts = RoastSelector(roasts: try! Roast.shipped(), randomIndex: { _ in 0 }, defaults: defaults)
    }

    deinit { defaults.removePersistentDomain(forName: suite) }

    func build(_ snapshots: [ProviderSnapshot], errors: [ProviderID: any Error] = [.codex: codexMissing],
               now: Date = noon) -> DisplaySnapshot {
        let builder = DisplayBuilder(prices: prices, cafe: try! CafeData.shipped(), water: try! WaterData.shipped(),
                                     defaults: defaults, calendar: madrid)
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
    #expect(s.indexLine == nil && s.roast == nil)
}

@Test func installedProviderWithoutDataIsNoData() {
    let s = Fixture(index: .cafe).build([snapshot()])
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

@Test(arguments: [IndexChoice?.none, .cafe, .tuition, .water])
func warningShowsTheLimitForEachIndex(index: IndexChoice?) {
    let s = Fixture(index: index).build([snapshot([record(eur: 6.12)], limits: [limit(87.9)])])
    #expect(s.state == .warning)
    #expect(s.menuBarText == "87%" && s.menuBarSymbol == "exclamationmark.triangle.fill")
}

@Test(arguments: [IndexChoice?.none, .cafe, .tuition, .water])
func limitHitShowsTimeToReset(index: IndexChoice?) {
    let resets = noon.addingTimeInterval(108 * 60)
    let s = Fixture(index: index).build([snapshot([record(eur: 6.12)], limits: [limit(100, resets: resets), limit(30, name: "weekly")])])
    #expect(s.state == .limitHit)
    #expect(s.menuBarText == "1h48" && s.menuBarSymbol == "hourglass")
    #expect(MenuBarLabel.voiceOverLabel(s, now: noon) == "TokenBar. Claude Code limit reached. Resets in 1 hour, 48 minutes.")
}

@Test func passedResetShowsZero() {
    let s = Fixture().build([snapshot(limits: [limit(100, resets: noon.addingTimeInterval(-1))])])
    #expect(s.rows[0].limits[0].usedPercent == 0)
    #expect(s.state == .normal && s.menuBarText == "0%")
}

// MARK: - Auto metric and indexes

@Test func autoMetricIsTheHighestLimit() {
    let s = Fixture().build([snapshot([record(eur: 3.4)], limits: [limit(30)]), snapshot(limits: [limit(62, name: "weekly")], of: .codex)],
                            errors: [:])
    #expect(s.menuBarText == "62%" && s.menuBarSymbol == "circle.lefthalf.filled")
    #expect(MenuBarLabel.voiceOverLabel(s, now: noon) == "TokenBar. Codex, 62 percent of weekly limit.")
}

/// D42: no EUR in the menu bar. Without a limit and an index value, the item shows only the symbol.
@Test func noLimitAndNoIndexValueShowsOnlyTheSymbol() {
    let s = Fixture().build([snapshot([record(eur: 3.4)])])
    #expect(s.menuBarText == "" && s.menuBarSymbol == "circle.lefthalf.filled")
    #expect(MenuBarLabel.voiceOverLabel(s, now: noon) == "TokenBar.")
}

@Test func noIndexYetHasNoJokes() {
    let s = Fixture().build([snapshot([record(eur: 6.12)], limits: [limit(62)])])
    #expect(s.index == nil)
    #expect(s.indexLine == nil && s.indexSymbol == nil && s.roast == nil)
    #expect(s.lastRefresh == noon)
}

@Test func noIndexYetShowsThePrimaryMetric() {
    let s = Fixture().build([snapshot([record(eur: 6.12)], limits: [limit(62)])])
    #expect(s.index == nil && s.menuBarText == "62%" && s.roast == nil)
}

@Test func cafeShowsOnlyTheCafeValue() {
    let s = Fixture(index: .cafe).build([snapshot([record(eur: 6.12, output: 200_000)], limits: [limit(62)])])
    #expect(s.menuBarText == "3.4" && s.menuBarSymbol == "cafe")
    #expect(s.indexLine == "3.4 cafés con leche today" && s.indexSymbol == "cafe" && s.indexEmoji == "☕")
    #expect(s.indexDetail == "3.4 this week")
    #expect(s.roast != nil)
    #expect(MenuBarLabel.voiceOverLabel(s, now: noon) == "TokenBar. Claude Code, 62 percent of 5-hour limit. 3.4 cafés con leche today.")
}

/// €46.80 of €114,000 is 0.04%. On the first day, the spend since install is today's cost.
@Test func tuitionShowsTheShareOfTuition() {
    let s = Fixture(index: .tuition).build([snapshot([record(eur: 46.80, output: 200_000)], limits: [limit(62)])])
    #expect(s.menuBarText == "0.04%" && s.menuBarSymbol == "tuition")
    #expect(s.indexLine == "0.04% of your MBA tuition, in tokens (since install)" && s.indexEmoji == "🎓")
    #expect(MenuBarLabel.voiceOverLabel(s, now: noon)
            == "TokenBar. Claude Code, 62 percent of 5-hour limit. 0.04% of your MBA tuition, in tokens (since install).")
    #expect(s.indexDetail == nil)  // less than 1 day since install
}

/// One day after install: €46.80 a day, €116,906 left ≈ 6.8 years, so 2026 + 7.
@Test func tuitionShowsTheBurnYearAfterOneDay() {
    let f = Fixture(index: .tuition)
    _ = f.build([snapshot([record(eur: 46.80)])])
    let tomorrow = noon.addingTimeInterval(24 * 3600)
    let s = f.build([snapshot([record(eur: 46.80), record(eur: 0.01, at: tomorrow.addingTimeInterval(-60))])], now: tomorrow)
    #expect(s.indexDetail == "At this pace, you'll burn through it by the year 2033.")
    #expect(ShareCard.text(s).contains("by the year 2033."))
    // The café second line is the week in the same unit: €46.80 / €10 = 4.7 menús del día.
    #expect(Fixture(index: .cafe).build([snapshot([record(eur: 46.80)])]).indexDetail == "4.7 this week")
}

/// 200k output tokens × 0.1125 mL = 22.5 L. Input tokens do not count.
@Test func waterShowsLitresFromOutputTokens() {
    let f = Fixture(index: .water)
    let s = f.build([snapshot([record(eur: 6.12, output: 150_000), record(eur: 1, output: 50_000),
                               record(eur: 9, at: noon.addingTimeInterval(-24 * 3600), output: 900_000)], limits: [limit(62)])])
    #expect(s.menuBarText == "22 L" && s.menuBarSymbol == "water")
    // The week has 1.1M output tokens: 123.75 L.
    #expect(s.indexLine == "22 L of water today" && s.indexDetail == "15 bottles (1.5 L) · 124 L this week" && s.indexEmoji == "💧")
    #expect(MenuBarLabel.voiceOverLabel(s, now: noon)
            == "TokenBar. Claude Code, 62 percent of 5-hour limit. 22 L of water today.")
    // No output today: the menu bar shows the primary metric. The popover headline shows 0.
    let zero = Fixture(index: .water).build([snapshot([record(eur: 6.12)], limits: [limit(62)])])
    #expect(zero.menuBarText == "62%")
    #expect(zero.indexLine == "0 mL of water today" && zero.indexDetail == "0 mL this week")
}

/// No cost today, but data from yesterday: the headline shows 0, and the week in the same unit.
@Test func cafeHeadlineAtZeroToday() {
    let s = Fixture(index: .cafe).build([snapshot([record(eur: 3.6, at: noon.addingTimeInterval(-24 * 3600))], limits: [limit(10)])])
    #expect(s.menuBarText == "10%")
    #expect(s.indexLine == "0 cafés con leche today" && s.indexDetail == "2.0 this week" && s.indexSymbol == "cafe")
}

/// Each index fills only its own placeholders, so a roast never shows a second index (D41).
@Test(arguments: IndexChoice.allCases)
func roastsUseOnlyTheSelectedIndex(index: IndexChoice) {
    let f = Fixture(index: index)
    f.roasts = RoastSelector(roasts: [Roast(id: "cafe", text: "{unit_value}", category: .career, locale: "en"),
                                      Roast(id: "tuition", text: "{tuition_percent}", category: .career, locale: "en"),
                                      Roast(id: "water", text: "{water}", category: .water, locale: "en")],
                             randomIndex: { _ in 0 }, defaults: f.defaults)
    let s = f.build([snapshot([record(eur: 6.12, output: 200_000)], limits: [limit(62)])])
    let expected: [IndexChoice: String] = [.cafe: "3.4", .tuition: "0.01%", .water: "22 L"]
    #expect(s.roast == expected[index])
}

@Test func roastsToggleTurnsRoastsOff() {
    let f = Fixture(index: .cafe)
    f.defaults.set(false, forKey: SettingsKey.roastsEnabled)
    let s = f.build([snapshot([record(eur: 6.12)], limits: [limit(62)])])
    #expect(s.menuBarText == "3.4" && s.indexLine != nil && s.roast == nil)
}

@Test func errorHasNoRoast() {
    let s = Fixture(index: .cafe).build([snapshot([record(eur: 6.12)])], errors: [.claudeCode: ReadError(), .codex: codexMissing])
    #expect(s.state == .error && s.roast == nil)
}

@Test func cafeUnitStaysForTheDay() {
    let f = Fixture(index: .cafe)
    #expect(f.build([snapshot([record(eur: 6.12)])]).menuBarText == "3.4")  // café con leche is closest to 3
    // A fresh pick for €10.50 is pa amb tomàquet (3.0). The café con leche stays while it is in range.
    #expect(f.build([snapshot([record(eur: 10.5)])]).indexLine == "5.8 cafés con leche today")
    let tomorrow = noon.addingTimeInterval(24 * 3600)
    let next = f.build([snapshot([record(eur: 10.5, at: tomorrow)])], now: tomorrow)
    #expect(next.indexLine == "3.0 pa amb tomàquets today" && next.indexSymbol == "cafe")
}

// MARK: - Costs

@Test func costsForTodayAndWeek() {
    let records = [record(eur: 2), record(eur: 3, at: noon.addingTimeInterval(-3 * 24 * 3600)),
                   record(eur: 50, at: noon.addingTimeInterval(-8 * 24 * 3600))]
    let s = Fixture(index: .cafe).build([snapshot(records), snapshot([record(.codex, eur: 1)], of: .codex)], errors: [:])
    // €3 today and €6 this week, in cafés con leche (€1.80). The EUR values stay internal (D42).
    #expect(s.indexLine == "1.7 cafés con leche today" && s.indexDetail == "3.3 this week")
    #expect(s.rows.allSatisfy { !$0.hasUnpricedModels } && !PopoverFormat.notCounted(s))
}

@Test func unpricedModelIsFlagged() {
    let s = Fixture(index: .cafe).build([snapshot([record(eur: 1, model: "unknown-model")])])
    #expect(s.rows[0].hasUnpricedModels && !s.rows[1].hasUnpricedModels)
    #expect(s.indexLine == "0 cafés con leche today")  // usage today, but no known price
    #expect(PopoverFormat.notCounted(s))
    // The Water Footprint counts tokens, not prices.
    #expect(!PopoverFormat.notCounted(Fixture(index: .water).build([snapshot([record(eur: 1, model: "unknown-model")])])))
}

@Test func shortFormats() {
    #expect([42, 108, 599, 1439, 3 * 1440].map { DisplayBuilder.shortDuration(Double($0) * 60) } == ["42m", "1h48", "9h59", "23h", "3d"])
}

// MARK: - Width

/// The longest text that each state can show, with its symbol (DRD 2.2: max 52 pt).
@Test func longestLabelsFit() {
    let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    let normal = "circle.lefthalf.filled"
    var labels: [(String, String)] = [
        ("", "circle.dashed"), ("", "exclamationmark.circle"),
        ("100%", "hourglass"), ("9h59", "hourglass"), ("23h", "hourglass"), ("59m", "hourglass"), ("99d", "hourglass"),
        ("99%", "exclamationmark.triangle.fill"),
        ("79%", normal), ("", normal),
        ("0.5", "cafe"), ("9.9", "cafe"), ("20", "cafe"), ("999", "cafe"),  // all café units use the café icon (D43)
    ]
    // The longest Water Footprint values (D41).
    labels += ["0.1 L", "9.9 L", "999 L", "9.9kL", "99kL"].map { ($0, "water") }
    for (text, symbol) in labels {
        let image = Icon.image(symbol, pointSize: font.pointSize)
        #expect(image.size.width > 0, "\(symbol) is missing")
        let textWidth = text.isEmpty ? 0 : NSAttributedString(string: text, attributes: [.font: font]).size().width + MenuBarLabel.spacing
        #expect(image.size.width + textWidth <= MenuBarLabel.width, "\(symbol) \(text): \(image.size.width + textWidth) pt")
        #expect(MenuBarLabel.image(symbol: symbol, text: text).size.width == MenuBarLabel.width)
    }
}

/// D41: the Tuition Meter has 68 pt for "0.04%", in each state. The advance width of "0.04%" is 64.07 pt,
/// so the test checks the drawn pixels: the last column of the image must be empty.
@Test func tuitionLabelsFit68Points() throws {
    let tuition = MenuBarLabel.width(.tuition)
    #expect(tuition == 68)
    let labels: [(String, String)] = ["<.01%", "0.04%", "12.3%", "99.9%", "123%"].map { ($0, "tuition") }
        + [("99%", "exclamationmark.triangle.fill"), ("100%", "hourglass"), ("9h59", "hourglass")]
    for (text, symbol) in labels {
        let image = MenuBarLabel.image(symbol: symbol, text: text, width: tuition)
        #expect(image.size.width == tuition)
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(tuition) * 2, pixelsHigh: Int(image.size.height) * 2,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let lastColumn = (0..<rep.pixelsHigh).map { rep.colorAt(x: rep.pixelsWide - 1, y: $0)?.alphaComponent ?? 0 }
        #expect(lastColumn.allSatisfy { $0 < 0.05 }, "\(symbol) \(text) is cut at \(tuition) pt")
    }
}

@Test func barValueKeepsOneDecimalBelowOne() {
    #expect(DisplayBuilder.barValue("0.49") == "0.5")
    #expect(DisplayBuilder.barValue("0.04") == "0.1")
    #expect(DisplayBuilder.barValue("3.4") == "3.4")
    #expect(DisplayBuilder.barValue("12") == "12")
}

/// The content is centered, so the open item highlight has the same margin on each side.
@Test func labelContentIsCentered() throws {
    for (symbol, text, width) in [("cafe", "2.4", MenuBarLabel.width), ("water", "12 L", MenuBarLabel.width),
                                  ("tuition", "0.04%", MenuBarLabel.tuitionWidth)] {
        let image = MenuBarLabel.image(symbol: symbol, text: text, width: width)
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * 2, pixelsHigh: Int(image.size.height) * 2,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let inked = (0..<rep.pixelsWide).filter { x in (0..<rep.pixelsHigh).contains { (rep.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.05 } }
        let left = try #require(inked.first), right = rep.pixelsWide - 1 - (try #require(inked.last))
        #expect(abs(left - right) <= 4, "\(symbol) \(text): left \(left) px, right \(right) px")
    }
}
