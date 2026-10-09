import Foundation
import Testing
@testable import TokenBar

private let water = try! WaterData.shipped()

@Test func shippedWaterFileHasSourceAndDate() {
    #expect(water.mlPerOutputToken == 0.1125)  // 45 mL / 400 output tokens
    #expect(water.source.hasPrefix("https://mistral.ai/"))
    #expect(water.lastVerified == "2026-10-09")
    #expect(water.units.map(\.ml) == [250, 1500, 150_000])
}

@Test func decodeRejectsBadFactorOrUnits() {
    for json in [#"{"ml_per_output_token": 0, "source": "s", "last_verified": "d", "units": [{"id": "a", "singular": "a", "plural": "a", "ml": 1}]}"#,
                 #"{"ml_per_output_token": 1, "source": "s", "last_verified": "d", "units": []}"#,
                 #"{"ml_per_output_token": 1, "source": "s", "last_verified": "d", "units": [{"id": "a", "singular": "a", "plural": "a", "ml": 0}]}"#] {
        #expect(throws: (any Error).self) { try WaterData.decode(Data(json.utf8)) }
    }
}

@Test func waterFromOutputTokens() {
    #expect(water.ml(outputTokens: 400) == 45)
    let ml = water.ml(outputTokens: 200_000)
    #expect(ml == 22_500)
    #expect(water.line(ml: ml) == "Today ≈ 22 L of water · 15 bottles (1.5 L)")
    #expect(WaterData.barValue(ml) == "22 L")
    #expect(water.line(ml: water.ml(outputTokens: 2_000_000)) == "Today ≈ 225 L of water · 1.5 bathtubs (150 L)")
    #expect(water.line(ml: 45) == "Today ≈ 45 mL of water · 0.2 glasses (250 mL)")
    #expect(water.line(ml: 250) == "Today ≈ 250 mL of water · 1.0 glass (250 mL)")
}

@Test func waterFormats() {
    #expect([45, 999, 1000, 9_940, 22_500, 999_400, 1_125_000, 99_000_000].map(WaterData.amount)
            == ["45 mL", "999 mL", "1.0 L", "9.9 L", "22 L", "999 L", "1125 L", "99000 L"])
    #expect([45, 9_940, 22_500, 999_400, 1_125_000, 99_000_000].map(WaterData.barValue)
            == ["0.1 L", "9.9 L", "22 L", "999 L", "1.1kL", "99kL"])
}
