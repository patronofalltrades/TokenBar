import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TokenBar

@MainActor @Suite struct LeaderboardViewTests {
    private let now = PopoverSamples.now
    private func card(_ index: IndexChoice) throws -> LeaderboardCardData {
        let members = (1...5).map {
            LeaderboardMember(handle: "member\($0)", asOf: "2026-11-25", weekCostEUR: Double($0) * 3.3,
                              weekOutputTokens: $0 * 12_345, spendSinceInstallEUR: Double($0) * 41.7)
        }
        return LeaderboardCardData(code: "cafe-k3m9-x7q2", index: index,
                                   entries: LeaderboardRanking.entries(members, index: index, me: "member2",
                                                                       cafe: try .shipped(), water: try .shipped()),
                                   updatedAt: now.addingTimeInterval(-300))
    }

    @Test func popoverWithCardRendersAndStaysBelow560() throws {
        let snapshot = try #require(PopoverSamples.all.first).snapshot
        for index in IndexChoice.allCases {
            let image = try #require(ImageRenderer(content: PopoverView(snapshot: snapshot, leaderboard: try card(index), now: now)).nsImage)
            #expect(image.size.width == 320)
            #expect(image.size.height <= 560)
        }
    }

    @Test func cardTextHasNoCurrencyAndNamesYourRank() throws {
        for index in IndexChoice.allCases {
            let data = try card(index)
            #expect(data.headline == "You are #4 of 5")
            #expect(data.top.map(\.handle) == data.entries.prefix(3).map(\.handle))
            let text = data.voiceOver + (data.headline ?? "") + data.entries.map(\.text).joined()
            for banned in ["€", "EUR", "euro"] { #expect(!text.localizedCaseInsensitiveContains(banned), "\(banned) in \(text)") }
        }
    }

    @Test func cardHasNoHeadlineWhenYouAreNotOnTheBoard() throws {
        var data = try card(.cafe)
        data = LeaderboardCardData(code: data.code, index: .cafe, entries: data.entries.map {
            .init(rank: $0.rank, handle: $0.handle, value: $0.value, text: $0.text, isMe: false)
        }, updatedAt: data.updatedAt)
        #expect(data.headline == nil)
    }

    @Test func settingsRenderNotSetUp() {
        #expect(ImageRenderer(content: LeaderboardSettings(model: nil).frame(width: 480)).nsImage != nil)
    }

    @Test func modelWithoutAddressIsNotConfiguredAndHasNoCard() throws {
        let suite = "LbModel.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SettingsKey.leaderboardEnabled)
        defaults.set("cafe-k3m9-x7q2", forKey: SettingsKey.leaderboardCode)
        defaults.set("ana", forKey: SettingsKey.leaderboardHandle)
        let model = LeaderboardModel(client: nil, tokens: KeychainTokenStore(), defaults: defaults)
        #expect(!model.isConfigured)
        #expect(model.card(index: .cafe, cafe: try .shipped(), water: try .shipped()) == nil)
    }

    /// The shipped file has no server address until the maintainer deploys the server (D62, TRD 17.1 rule 2).
    @Test func shippedConfigHasNoAddress() throws {
        #expect(try LeaderboardConfig.shipped().url == nil)
    }
}
