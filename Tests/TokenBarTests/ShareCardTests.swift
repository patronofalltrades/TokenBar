import AppKit
import Foundation
import Testing
@testable import TokenBar

private let secret = "SECRET-MARKER"

@Test func cafeCardText() {
    #expect(ShareCard.text(PopoverSamples.normal) == """
        ☕ 3.4 cafés con leche today
        12 this week
        €6.12 of tokens ÷ €1.80 per café con leche

        “The protagonist has 38% of Opus left and a 9 AM deadline. Discuss.”

        TokenBar · github.com/patronofalltrades/TokenBar
        """)
}

@Test func tuitionCardText() {
    #expect(ShareCard.text(PopoverSamples.tuition) == """
        🎓 0.04% of your MBA tuition, in tokens (since install)
        At this pace, you'll burn through it by the year 4210.
        €45.60 of tokens since install ÷ €114,000 MBA tuition

        “0.04% of your MBA tuition, paid in tokens. The ROI case writes itself.”

        TokenBar · github.com/patronofalltrades/TokenBar
        """)
}

@Test func waterCardText() {
    #expect(ShareCard.text(PopoverSamples.water) == """
        💧 22 L of water today
        15 bottles (1.5 L) · 98 L this week
        195,556 output tokens × 0.1125 mL each (Mistral estimate)

        “Your prompts drank 22 L of water today. Somewhere a cooling tower is writing its own case study.”

        TokenBar · github.com/patronofalltrades/TokenBar
        """)
}

private let noIndex = DisplaySnapshot(
    state: .normal, index: nil, menuBarText: "", menuBarSymbol: "", rows: [],
    indexLine: "café", indexSymbol: nil, roast: "roast", lastRefresh: nil)

/// No index yet: no card lines, also when a snapshot has index lines. The popover has no Share button (D42).
@Test func noIndexCardHasNoLines() {
    #expect(ShareCard.lines(noIndex).isEmpty)
}

/// DRD 7.7 rule 5: only the index lines and the roast go onto the card.
@Test func cardLeaksNoOtherSnapshotText() {
    let row = DisplaySnapshot.ProviderRow(
        provider: .claudeCode, installed: true, errorText: "/Users/\(secret)/project \(secret)",
        limits: [.init(name: secret, usedPercent: 50, resetsAt: nil, observedAt: .now)],
        hasUnpricedModels: false)
    for index in IndexChoice.allCases + [nil] {
        let s = DisplaySnapshot(
            state: .normal, index: index, menuBarText: secret, menuBarSymbol: secret, rows: [row],
            indexLine: nil, indexSymbol: secret, roast: nil,
            lastRefresh: .now)
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
    defaults.set(IndexChoice.cafe.rawValue, forKey: SettingsKey.index)
    let prices = try PriceTable.decode(Data(#"""
        {"last_verified": "2026-10-08", "usd_to_eur": 1, "fx_updated": "2026-10-08", "fx_note": "n",
         "models": [{"id": "\#(secret)", "input": 1, "source": "s", "last_verified": "2026-10-08"}]}
        """#.utf8))
    let now = Date()
    let record = UsageRecord(provider: .claudeCode, model: secret, timestamp: now, tokens: TokenCounts(input: 5_000_000))
    var roasts = RoastSelector(roasts: [Roast(id: "r", text: text, category: .career, locale: "en")],
                               randomIndex: { _ in 0 }, defaults: defaults)
    let s = DisplayBuilder(prices: prices, cafe: try CafeData.shipped(), water: try WaterData.shipped(), defaults: defaults).build(
        snapshots: [.claudeCode: ProviderSnapshot(provider: .claudeCode, records: [record], limits: [], updatedAt: now)],
        errors: [:], lastRefresh: now, now: now, roasts: &roasts, tuition: TuitionTotal(defaults: defaults))
    let card = ShareCard.text(s)
    #expect(card.hasPrefix("☕ 2.8 cafés con leche today\n"))  // €5 / €1.80
    #expect(card.contains(secret) == shows)
}

@MainActor @Test func imageIs360PointsWideAtScale2() throws {
    for sample in [PopoverSamples.normal, PopoverSamples.tuition, PopoverSamples.water] {
        let image = try #require(ShareCard.image(sample))
        #expect(image.width == 720)
        #expect(image.height > 100 && image.height < 720)
        // Set SHARE_CARD_PNG_DIR to save the images for a visual check.
        if let dir = ProcessInfo.processInfo.environment["SHARE_CARD_PNG_DIR"] {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("share-card-\(sample.index?.rawValue ?? "none").png"))
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
