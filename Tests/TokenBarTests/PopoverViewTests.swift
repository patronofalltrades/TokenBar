import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TokenBar

private let gb = Locale(identifier: "en_GB")
private let utc = TimeZone(identifier: "UTC")!
private let now = PopoverSamples.now  // Sunday 14:05 UTC

@MainActor @Test(arguments: PopoverSamples.all.map(\.name))
func sampleRendersAt320Points(name: String) throws {
    let snapshot = try #require(PopoverSamples.all.first { $0.name == name }).snapshot
    let renderer = ImageRenderer(content: PopoverView(snapshot: snapshot, now: now))
    let image = try #require(renderer.nsImage)
    #expect(image.size.width == 320)
    #expect(image.size.height > 100 && image.size.height <= 560)
    // Set POPOVER_PNG_DIR to save the images for a visual check. NSHostingView also draws buttons,
    // which ImageRenderer cannot draw.
    if let dir = ProcessInfo.processInfo.environment["POPOVER_PNG_DIR"] {
        let host = NSHostingView(rootView: PopoverView(snapshot: snapshot, now: now))
        host.frame.size = host.fittingSize
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}

@Test func resetUsesRelativeTimeBelow24Hours() {
    #expect(PopoverFormat.reset(now.addingTimeInterval(108 * 60), now: now) == "resets in 1 h 48 min")
    #expect(PopoverFormat.reset(now.addingTimeInterval(42 * 60), now: now) == "resets in 42 min")
    #expect(PopoverFormat.reset(now.addingTimeInterval(-60), now: now) == "resets in 0 min")
    #expect(PopoverFormat.reset(now.addingTimeInterval(108 * 60), now: now, spoken: true, locale: gb)
        == "resets in 1 hour, 48 minutes")
}

@Test func resetUsesWeekdayAndTimeFrom24Hours() {
    // Monday 09:00 UTC is 18 h 55 min after now; Tuesday 09:00 is 42 h 55 min after now.
    let tuesday = now.addingTimeInterval((42 * 60 + 55) * 60)
    #expect(PopoverFormat.reset(tuesday, now: now, locale: gb, timeZone: utc) == "resets Tue 9:00")
    #expect(PopoverFormat.reset(now.addingTimeInterval(24 * 3600), now: now, locale: gb, timeZone: utc)
        == "resets Mon 14:05")
}

@Test func asOfTimeUsesLocaleAndTimeZone() {
    #expect(PopoverFormat.time(now, locale: gb, timeZone: utc) == "14:05")
    #expect(PopoverFormat.time(now, locale: gb, timeZone: TimeZone(identifier: "Europe/Madrid")!) == "16:05")
}


@Test func updatedText() {
    #expect(PopoverFormat.updated(now.addingTimeInterval(-30), now: now) == "Updated just now")
    #expect(PopoverFormat.updated(now.addingTimeInterval(-120), now: now) == "Updated 2 min ago")
    #expect(PopoverFormat.updated(now.addingTimeInterval(-3 * 3600), now: now) == "Updated 3 h ago")
}

@Test func barColorThresholds() {
    #expect(PopoverFormat.barColor(79.9) == Theme.coffee)
    #expect(PopoverFormat.barColor(80) == Theme.warning)
    #expect(PopoverFormat.barColor(99) == Theme.warning)
    #expect(PopoverFormat.barColor(100) == Theme.danger)
}

/// DRD 8.1 rule 4: the three bar colors are far apart in light and dark mode. PR #28 had 0.16 between normal and warning.
@Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
func barColorsDiffer(appearance: NSAppearance.Name) throws {
    func rgb(_ color: Color) throws -> [CGFloat] {
        var resolved: NSColor?
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        let c = try #require(resolved)
        return [c.redComponent, c.greenComponent, c.blueComponent]
    }
    func distance(_ a: Color, _ b: Color) throws -> CGFloat {
        sqrt(zip(try rgb(a), try rgb(b)).map { ($0 - $1) * ($0 - $1) }.reduce(0, +))
    }
    #expect(try rgb(Theme.coffee) != rgb(Theme.paper))  // the color is dynamic, not a fallback
    #expect(try distance(Theme.coffee, Theme.warning) >= 0.3)
    #expect(try distance(Theme.warning, Theme.danger) >= 0.3)
    #expect(try distance(Theme.coffee, Theme.danger) >= 0.3)
}

@Test func stillAvailableShowsWhatIsLeft() {
    let weekly = DisplaySnapshot.Limit(name: "weekly", usedPercent: 18, resetsAt: nil, observedAt: now)
    let fiveHour = DisplaySnapshot.Limit(name: "5-hour", usedPercent: 40.6, resetsAt: nil, observedAt: now)
    #expect(PopoverFormat.stillAvailable(.codex, weekly) == "Codex still available: 82% left this week")
    #expect(PopoverFormat.stillAvailable(.claudeCode, fiveHour) == "Claude Code still available: 60% left in this 5-hour window")
}

@Test func links() {
    #expect(Links.feedback.host == "tally.so")
    #expect(Links.repository.host == "github.com")
}

/// The snapshot text that the popover shows. The other popover text is literals in the UI files.
private func popoverText(_ s: DisplaySnapshot) -> String {
    let rows: [String?] = s.rows.flatMap { row -> [String?] in [row.errorText] + row.limits.map(\.name) }
    return ([s.indexLine, s.indexDetail, s.roast, s.menuBarText] + rows).compactMap { $0 }.joined(separator: "\n")
}

/// D42: no EUR in the popover and the share card, for each index and state. The samples and the
/// builder with the shipped roasts cover high spend, which used to fill `{cost}`.
@Test func noEuroInPopoverOrShareCard() throws {
    let suite = "NoEuro.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let prices = try PriceTable.decode(Data(#"""
        {"last_verified": "2026-10-08", "usd_to_eur": 1, "fx_updated": "2026-10-08", "fx_note": "n",
         "models": [{"id": "m", "input": 1, "source": "s", "last_verified": "2026-10-08"}]}
        """#.utf8))
    let shipped = try Roast.shipped()
    var built: [DisplaySnapshot] = []
    for index in [IndexChoice?.none] + IndexChoice.allCases {
        defaults.set(index?.rawValue, forKey: SettingsKey.index)
        for (eur, percent) in [(0.0, 10.0), (25.0, nil), (25.0, 87.0), (300.0, 100.0)] {
            for pick in 0..<shipped.count {
                var roasts = RoastSelector(roasts: shipped, randomIndex: { pick % max(1, $0) }, defaults: defaults)
                let records = [UsageRecord(provider: .claudeCode, model: "m", timestamp: now.addingTimeInterval(-60),
                                           tokens: TokenCounts(input: Int(eur * 1_000_000), output: 10_000)),
                               UsageRecord(provider: .codex, model: "unknown", timestamp: now.addingTimeInterval(-60),
                                           tokens: TokenCounts(input: 1))]
                let limits = percent.map { [LimitWindow(name: "5-hour", usedPercent: $0, resetsAt: now.addingTimeInterval(600), observedAt: now)] } ?? []
                built.append(DisplayBuilder(prices: prices, cafe: try CafeData.shipped(), water: try WaterData.shipped(), defaults: defaults).build(
                    snapshots: [.claudeCode: ProviderSnapshot(provider: .claudeCode, records: records.filter { $0.provider == .claudeCode },
                                                              limits: limits, updatedAt: now),
                                .codex: ProviderSnapshot(provider: .codex, records: records.filter { $0.provider == .codex }, limits: [], updatedAt: now)],
                    errors: [:], lastRefresh: now, now: now, roasts: &roasts, tuition: TuitionTotal(defaults: defaults)))
            }
        }
    }
    #expect(built.contains { $0.roast?.contains("API-equivalent") == false && $0.roast != nil })
    for s in PopoverSamples.all.map(\.snapshot) + built {
        let text = [popoverText(s), ShareCard.text(s), MenuBarLabel.voiceOverLabel(s, now: now), s.menuBarText].joined(separator: "\n")
        for banned in ["€", "EUR", "euro", "API-equivalent", "Price unknown"] {
            #expect(!text.localizedCaseInsensitiveContains(banned), "\(banned) in: \(text)")
        }
    }
    // The UI files have no EUR text either.
    let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/TokenBar/UI")
    for file in try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil) {
        let source = try String(contentsOf: file, encoding: .utf8)
        for banned in ["€", ".currency(", "euros", "API-equivalent", "Price unknown"] {
            #expect(!source.contains(banned), "\(banned) in \(file.lastPathComponent)")
        }
    }
}
