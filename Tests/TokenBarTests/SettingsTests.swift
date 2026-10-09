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

    @Test func seriousTurnsOffRoastsAndCafeIndex() {
        SettingsView.select(.serious, in: defaults)
        #expect(defaults.string(forKey: SettingsKey.barStyle) == "serious")
        #expect(defaults.object(forKey: SettingsKey.roastsEnabled) as? Bool == false)
        #expect(defaults.object(forKey: SettingsKey.cafeIndexEnabled) as? Bool == false)
    }

    @Test func funnyDoesNotTurnTogglesOn() {
        SettingsView.select(.serious, in: defaults)
        SettingsView.select(.funny, in: defaults)
        #expect(defaults.string(forKey: SettingsKey.barStyle) == "funny")
        #expect(defaults.object(forKey: SettingsKey.roastsEnabled) as? Bool == false)
        #expect(defaults.object(forKey: SettingsKey.cafeIndexEnabled) as? Bool == false)
    }

    @Test func funnyOnEmptyDefaultsWritesOnlyTheStyle() {
        SettingsView.select(.funny, in: defaults)
        #expect(defaults.object(forKey: SettingsKey.roastsEnabled) == nil)
        #expect(defaults.object(forKey: SettingsKey.cafeIndexEnabled) == nil)
    }

    @Test(arguments: [SettingsKey.roastsEnabled, SettingsKey.cafeIndexEnabled,
                      SettingsKey.alert95Enabled, SettingsKey.alertLimitEnabled])
    func toggleIsOnWhenKeyIsMissing(key: String) {
        #expect(AppStorage(wrappedValue: true, key, store: defaults).wrappedValue)
    }

    @Test func barStyleIsNilWhenKeyIsMissing() {
        #expect(AppStorage<BarStyle?>(SettingsKey.barStyle, store: defaults).wrappedValue == nil)
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
