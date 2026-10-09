import Foundation
import Testing
@testable import TokenBar

private let table = try! PriceTable.shipped()
private func d(_ s: String) -> Decimal { Decimal(string: s)! }
private func cost(_ model: String, _ tokens: TokenCounts) -> Decimal? {
    table.costEUR(UsageRecord(provider: .claudeCode, model: model, timestamp: .now, tokens: tokens))
}

// MARK: - Data file

@Test func shippedFileIsValidAndCited() throws {
    #expect(table.lastVerified == "2026-10-08")
    #expect(table.usdToEUR == d("0.894"))
    #expect(table.fxUpdated == "2026-10-08")
    #expect(table.fxNote.hasPrefix("community estimate"))
    for model in table.models {
        #expect(model.source.hasPrefix("https://"), "\(model.id)")
        #expect(model.lastVerified == "2026-10-08", "\(model.id)")
        let prices = model.prices.all + (model.longContext?.prices.all ?? [])
        #expect(prices.allSatisfy { $0 >= 0 }, "\(model.id)")
        #expect(model.prices.input != nil && model.prices.output != nil, "\(model.id)")
    }
}

@Test(arguments: ["claude-opus-5-5", "claude-opus-5", "claude-fable-5", "claude-fable-5-1", "claude-sonnet-5",
                  "claude-sonnet-5-5", "claude-opus-4-8", "claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-5-5",
                  "claude-haiku-4-5-20251001", "gpt-6-sol", "gpt-6-astra", "gpt-6-luna", "gpt-5.6-sol",
                  "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"])
func modelsSeenInLocalLogsHaveAPrice(model: String) {
    #expect(table.price(for: model) != nil)
}

private func json(models: String = #"[{"id": "m", "input": 1, "source": "s", "last_verified": "d"}]"#,
                  rate: String = "0.9", fxUpdated: String = "\"2026-10-08\"") -> Data {
    Data(#"{"last_verified": "d", "usd_to_eur": \#(rate), "fx_updated": \#(fxUpdated), "fx_note": "n", "models": \#(models)}"#.utf8)
}

@Test func validPriceFileDecodes() throws {
    #expect(try PriceTable.decode(json()).models.count == 1)
}

@Test func missingSourceOrDateRejectsFile() {
    #expect(throws: DecodingError.self) { try PriceTable.decode(json(models: #"[{"id": "m", "last_verified": "d"}]"#)) }
    #expect(throws: DecodingError.self) { try PriceTable.decode(json(models: #"[{"id": "m", "source": "s"}]"#)) }
    #expect(throws: PriceDataError.missingSource("m")) {
        try PriceTable.decode(json(models: #"[{"id": "m", "source": "", "last_verified": "d"}]"#))
    }
}

@Test func badPricesRatesAndIDsRejectFile() {
    #expect(throws: PriceDataError.badPrice("m")) {
        try PriceTable.decode(json(models: #"[{"id": "m", "output": -1, "source": "s", "last_verified": "d"}]"#))
    }
    #expect(throws: PriceDataError.badPrice("m")) {
        try PriceTable.decode(json(models: #"[{"id": "m", "source": "s", "last_verified": "d", "long_context": {"above_tokens": 10, "input": -1}}]"#))
    }
    #expect(throws: PriceDataError.badRate) { try PriceTable.decode(json(rate: "0")) }
    #expect(throws: PriceDataError.badRate) { try PriceTable.decode(json(rate: "-0.9")) }
    #expect(throws: PriceDataError.badRate) { try PriceTable.decode(json(fxUpdated: "\"\"")) }
    #expect(throws: DecodingError.self) { try PriceTable.decode(json(fxUpdated: "null")) }
    #expect(throws: PriceDataError.noModels) { try PriceTable.decode(json(models: "[]")) }
    let twice = #"[{"id": "m", "source": "s", "last_verified": "d"}, {"id": "m", "source": "s", "last_verified": "d"}]"#
    #expect(throws: PriceDataError.duplicateID("m")) { try PriceTable.decode(json(models: twice)) }
}

// MARK: - Model lookup (rules 2 and 3)

@Test func exactMatchThenDatedID() {
    #expect(table.price(for: "claude-opus-5")?.id == "claude-opus-5")
    #expect(table.price(for: "claude-opus-5-5")?.id == "claude-opus-5-5")
    #expect(table.price(for: "claude-haiku-4-5-20251001")?.id == "claude-haiku-4-5")
    #expect(table.price(for: "gpt-5.5-2026-04-23")?.id == "gpt-5.5")
}

@Test(arguments: ["codex-auto-review", "<synthetic>", "", "gpt-5.5-pro", "claude-opus-5-6", "claude-opus-5x"])
func unknownModelHasNoCost(model: String) {
    #expect(table.price(for: model) == nil)
    #expect(cost(model, TokenCounts(input: 1_000_000)) == nil)
}

// MARK: - Cost (rules 4 to 6)

@Test func eachTokenClassUsesItsOwnPrice() {
    let opus = table.price(for: "claude-opus-5-5")!
    let million = 1_000_000
    #expect(opus.usd(TokenCounts(input: million)) == 4)
    #expect(opus.usd(TokenCounts(output: million)) == 20)
    #expect(opus.usd(TokenCounts(cacheRead: million)) == d("0.2"))
    #expect(opus.usd(TokenCounts(cacheWrite5m: million)) == 5)
    #expect(opus.usd(TokenCounts(cacheWrite1h: million)) == 8)
    #expect(opus.usd(TokenCounts()) == 0)
}

@Test func costIsInEURWithExactDecimals() {
    // 1,234 in × $4 + 567 out × $20 + 89,000 read × $0.2 + 3,000 5m × $5 + 2,000 1h × $8, per 1M tokens.
    let tokens = TokenCounts(input: 1_234, output: 567, cacheRead: 89_000, cacheWrite5m: 3_000, cacheWrite1h: 2_000)
    let usd = d("0.004936") + d("0.01134") + d("0.0178") + d("0.015") + d("0.016")
    #expect(table.price(for: "claude-opus-5-5")!.usd(tokens) == usd)
    #expect(cost("claude-opus-5-5", tokens) == usd * d("0.894"))
    #expect(cost("claude-opus-5-5", tokens) == d("0.058177944"))
}

@Test func costFromUsageRecord() {
    let record = UsageRecord(provider: .codex, model: "gpt-6-sol", timestamp: .now, tokens: TokenCounts(output: 100_000))
    #expect(table.costEUR(record) == d("0.894"))
}

@Test func classWithNoPriceCostsZero() {
    // gpt-5.5 has no cache-write price. OpenAI has no 1-hour cache write.
    #expect(table.price(for: "gpt-5.5")!.usd(TokenCounts(cacheWrite5m: 1_000_000)) == 0)
    #expect(table.price(for: "gpt-6-sol")!.usd(TokenCounts(cacheWrite1h: 1_000_000)) == 0)
}

@Test func longPromptUsesLongContextPrices() {
    let sol = table.price(for: "gpt-6-sol")!
    // The prompt is all input classes: 200,000 + 72,000 = 272,000, which is not above the limit.
    #expect(sol.usd(TokenCounts(input: 200_000, output: 1_000_000, cacheRead: 72_000)) == d("0.4") + 10 + d("0.0144"))
    // One more token moves the full request to the long-context prices.
    #expect(sol.usd(TokenCounts(input: 200_001, output: 1_000_000, cacheRead: 72_000)) == d("0.800004") + 15 + d("0.0288"))
    let haiku = table.price(for: "claude-haiku-5-5")!
    #expect(haiku.usd(TokenCounts(input: 1, output: 1_000_000, cacheWrite1h: 100_000)) == d("0.0000005") + d("2.5") + d("0.1"))
    #expect(haiku.usd(TokenCounts(input: 1, output: 1_000_000)) == d("0.0000001") + d("0.5"))
}

/// IES-225: the cache gives the same cost and prices each record one time.
@Test func costCacheMatchesAndPrunes() throws {
    let table = try PriceTable.shipped()
    let model = try #require(table.models.first).id
    let day = Date(timeIntervalSince1970: 1_791_000_000)
    let old = UsageRecord(provider: .claudeCode, model: model, timestamp: day.addingTimeInterval(-50 * 86_400), tokens: TokenCounts(input: 1000))
    let new = UsageRecord(provider: .claudeCode, model: model, timestamp: day, tokens: TokenCounts(output: 500))
    let unknown = UsageRecord(provider: .codex, model: "no-such-model", timestamp: day, tokens: TokenCounts(input: 1))
    let cache = CostCache()
    for r in [old, new, unknown, new] { #expect(cache.costEUR(r, prices: table) == table.costEUR(r)) }
    #expect(cache.count == 3)
    cache.prune(before: day.addingTimeInterval(-40 * 86_400), day: day)
    #expect(cache.count == 2)
}
