import AppKit
import Foundation
import Testing
@testable import TokenBar

private let gb = Locale(identifier: "en_GB")
private let secret = "SECRET-MARKER"

@Test func funnyCardText() {
    #expect(ShareCard.text(PopoverSamples.normal, locale: gb) == """
        ☕ Today = 3.4 cafés con leche
        🎓 0.04% of your MBA tuition, in tokens

        “The protagonist has 38% of Opus left and a 9 AM deadline. Discuss.”

        TokenBar · github.com/patronofalltrades/TokenBar
        """)
}

@Test func seriousCardShowsNumbersOnly() {
    #expect(ShareCard.text(PopoverSamples.serious, locale: gb) == """
        Today ≈ €6.10
        Week ≈ €21.80 (API-equivalent)

        TokenBar · github.com/patronofalltrades/TokenBar
        """)
}

/// Serious is numbers only, also when a snapshot has funny lines.
@Test func seriousCardIgnoresFunnyLines() {
    let s = DisplaySnapshot(
        state: .normal, barStyle: .serious, menuBarText: "", menuBarSymbol: "", rows: [], costTodayEUR: 1, costWeekEUR: 2,
        cafeLine: "café", cafeSymbol: nil, tuitionLine: "tuition", roast: "roast", lastRefresh: nil, pricesVerified: "")
    let text = ShareCard.text(s, locale: gb)
    #expect(!text.contains("café") && !text.contains("tuition") && !text.contains("roast"))
}

/// DRD 7.7 rule 5: only the café line, the tuition line, the roast and the costs go onto the card.
@Test func cardLeaksNoOtherSnapshotText() {
    let row = DisplaySnapshot.ProviderRow(
        provider: .claudeCode, installed: true, errorText: "/Users/\(secret)/project \(secret)",
        limits: [.init(name: secret, usedPercent: 50, resetsAt: nil, observedAt: .now)],
        costTodayEUR: 1, hasUnpricedModels: false)
    for style in [BarStyle.funny, .serious, nil] {
        let s = DisplaySnapshot(
            state: .normal, barStyle: style, menuBarText: secret, menuBarSymbol: secret, rows: [row],
            costTodayEUR: 1, costWeekEUR: 2, cafeLine: nil, cafeSymbol: secret, tuitionLine: nil, roast: nil,
            lastRefresh: .now, pricesVerified: secret)
        #expect(!ShareCard.text(s).contains(secret))
        #expect(!ShareCard.lines(s).contains { $0.text.contains(secret) })
    }
}

/// End to end from the logs: the model name gets onto the card only through a `{model}` roast.
@Test(arguments: [("Model {model} again.", true), ("No model here.", false)])
func modelOnlyThroughRoast(text: String, shows: Bool) throws {
    let suite = "ShareCardTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(BarStyle.funny.rawValue, forKey: SettingsKey.barStyle)
    let prices = try PriceTable.decode(Data(#"""
        {"last_verified": "2026-10-08", "usd_to_eur": 1, "fx_updated": "2026-10-08", "fx_note": "n",
         "models": [{"id": "\#(secret)", "input": 1, "source": "s", "last_verified": "2026-10-08"}]}
        """#.utf8))
    let now = Date()
    let record = UsageRecord(provider: .claudeCode, model: secret, timestamp: now, tokens: TokenCounts(input: 5_000_000))
    var roasts = RoastSelector(roasts: [Roast(id: "r", text: text, category: .career, locale: "en")],
                               randomIndex: { _ in 0 }, defaults: defaults)
    let s = DisplayBuilder(prices: prices, cafe: try CafeData.shipped(), defaults: defaults).build(
        snapshots: [.claudeCode: ProviderSnapshot(provider: .claudeCode, records: [record], limits: [], updatedAt: now)],
        errors: [:], lastRefresh: now, now: now, roasts: &roasts, tuition: TuitionTotal(defaults: defaults))
    let card = ShareCard.text(s)
    #expect(card.contains("☕ Today = ") || card.contains("🍅 Today = ") || card.contains("🥔 Today = "))
    #expect(card.contains(secret) == shows)
}

@MainActor @Test func imageIs360PointsWideAtScale2() throws {
    for sample in [PopoverSamples.normal, PopoverSamples.serious] {
        let image = try #require(ShareCard.image(sample))
        #expect(image.width == 720)
        #expect(image.height > 100 && image.height < 720)
        // Set SHARE_CARD_PNG_DIR to save the images for a visual check.
        if let dir = ProcessInfo.processInfo.environment["SHARE_CARD_PNG_DIR"] {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("share-card-\(sample.barStyle!.rawValue).png"))
        }
    }
}

@MainActor @Test func copyWritesImageAndTextInOneItem() throws {
    let pasteboard = NSPasteboard(name: .init("ShareCardTests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    #expect(ShareCard.copy(PopoverSamples.normal, to: pasteboard))
    let item = try #require(pasteboard.pasteboardItems?.first)
    #expect(pasteboard.pasteboardItems?.count == 1)
    #expect(item.string(forType: .string) == ShareCard.text(PopoverSamples.normal))
    let png = try #require(item.data(forType: .png))
    #expect(NSImage(data: png) != nil)
}
