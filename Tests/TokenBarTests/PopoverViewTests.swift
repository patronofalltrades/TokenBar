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

@Test func euroFormat() {
    #expect(PopoverFormat.euro(Decimal(string: "2.1")!, locale: gb) == "≈ €2.10")
    #expect(PopoverFormat.euro(Decimal(string: "6.1")!, approx: false, locale: gb) == "€6.10")
    #expect(PopoverFormat.euro(Decimal(string: "2.1")!, locale: Locale(identifier: "es_ES")) == "≈ 2,10\u{00A0}€")
}

@Test func updatedText() {
    #expect(PopoverFormat.updated(now.addingTimeInterval(-30), now: now) == "Updated just now")
    #expect(PopoverFormat.updated(now.addingTimeInterval(-120), now: now) == "Updated 2 min ago")
    #expect(PopoverFormat.updated(now.addingTimeInterval(-3 * 3600), now: now) == "Updated 3 h ago")
}

@Test func barColorThresholds() {
    #expect(PopoverFormat.barColor(79.9) == .accentColor)
    #expect(PopoverFormat.barColor(80) == .orange)
    #expect(PopoverFormat.barColor(99) == .orange)
    #expect(PopoverFormat.barColor(100) == .red)
}

@Test func links() {
    #expect(Links.feedback.host == "tally.so")
    #expect(Links.repository.host == "github.com")
}
