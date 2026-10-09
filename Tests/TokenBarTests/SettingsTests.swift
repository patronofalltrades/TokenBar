import Foundation
import SwiftUI
import Testing
@testable import TokenBar

@MainActor
struct SettingsTests {
    let defaults: UserDefaults

    init() {
        let suite = "SettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    /// D41: funny becomes café, serious asks again in onboarding. The old keys go away.
    @Test(arguments: [("funny", IndexChoice?.some(.cafe)), ("serious", nil), ("loud", nil)])
    func migratesTheOldBarStyleOneTime(old: String, expected: IndexChoice?) {
        defaults.set(old, forKey: "barStyle")
        defaults.set(false, forKey: "cafeIndexEnabled")
        defaults.set(false, forKey: SettingsKey.roastsEnabled)
        #expect(IndexChoice.saved(in: defaults) == expected)
        #expect(defaults.object(forKey: "barStyle") == nil && defaults.object(forKey: "cafeIndexEnabled") == nil)
        #expect(defaults.object(forKey: SettingsKey.roastsEnabled) as? Bool == false)  // the user choice stays
        defaults.set("water", forKey: SettingsKey.index)
        #expect(IndexChoice.saved(in: defaults) == .water)  // one time only
    }

    @Test func migrationKeepsANewChoice() {
        defaults.set("tuition", forKey: SettingsKey.index)
        defaults.set("funny", forKey: "barStyle")
        #expect(IndexChoice.saved(in: defaults) == .tuition)
    }

    @Test func noChoiceStaysNil() {
        #expect(IndexChoice.saved(in: defaults) == nil)
        #expect(IndexChoice.allCases.map(\.title) == ["Café Index", "Tuition Meter", "Water Footprint"])
    }

    @Test(arguments: [SettingsKey.roastsEnabled,
                      SettingsKey.alert95Enabled, SettingsKey.alertLimitEnabled])
    func toggleIsOnWhenKeyIsMissing(key: String) {
        #expect(AppStorage(wrappedValue: true, key, store: defaults).wrappedValue)
    }

    @Test func indexIsNilWhenKeyIsMissing() {
        #expect(AppStorage<IndexChoice?>(SettingsKey.index, store: defaults).wrappedValue == nil)
    }

    @Test func snippetIsExactAndValidJSON() throws {
        let expected = #"{"statusLine": {"type": "command", "command": "~/Applications/TokenBar.app/Contents/MacOS/TokenBar --statusline"}}"#
        #expect(SettingsView.statusLineSnippet == expected)
        let json = try JSONSerialization.jsonObject(with: Data(expected.utf8)) as? [String: [String: String]]
        #expect(json?["statusLine"]?["type"] == "command")
        #expect(json?["statusLine"]?["command"] == "~/Applications/TokenBar.app/Contents/MacOS/TokenBar --statusline")
    }

    @Test func claudeStatusText() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        #expect(GeneralSettings.statusText(.notConnected, now: now) == "Not connected")
        #expect(GeneralSettings.statusText(.connectedWaiting, now: now) == "Connected. Waiting for the next Claude Code reply.")
        #expect(GeneralSettings.statusText(.connected(updatedAt: now.addingTimeInterval(-180)), now: now).hasPrefix("Connected · updated 3 min"))
    }

    @Test func tabsRender() {
        #expect(ImageRenderer(content: SettingsView()).nsImage != nil)
        #expect(ImageRenderer(content: GeneralSettings().frame(width: 480)).nsImage != nil)
        #expect(ImageRenderer(content: AlertSettings().frame(width: 480)).nsImage != nil)
        #expect(ImageRenderer(content: AboutSettings().frame(width: 480)).nsImage != nil)
    }
}
