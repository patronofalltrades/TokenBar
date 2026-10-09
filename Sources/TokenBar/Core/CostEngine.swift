import Foundation

/// USD per 1M tokens for each token class. A class with no price costs 0 (TRD 6, rule 5).
struct TokenPrices: Decodable, Sendable {
    let input, output, cacheRead, cacheWrite5m, cacheWrite1h: Decimal?

    enum CodingKeys: String, CodingKey {
        case input, output
        case cacheRead = "cache_read", cacheWrite5m = "cache_write_5m", cacheWrite1h = "cache_write_1h"
    }

    var all: [Decimal] { [input, output, cacheRead, cacheWrite5m, cacheWrite1h].compactMap { $0 } }

    func usd(_ t: TokenCounts) -> Decimal {
        let pairs: [(Int, Decimal?)] = [(t.input, input), (t.output, output), (t.cacheRead, cacheRead),
                                        (t.cacheWrite5m, cacheWrite5m), (t.cacheWrite1h, cacheWrite1h)]
        return pairs.reduce(Decimal(0)) { $0 + Decimal($1.0) * ($1.1 ?? 0) } / 1_000_000
    }
}

/// Higher prices for a prompt above `aboveTokens`, for example OpenAI above 272K input tokens.
struct LongContextPrices: Decodable, Sendable {
    let aboveTokens: Int
    let prices: TokenPrices

    enum CodingKeys: String, CodingKey { case aboveTokens = "above_tokens" }

    init(from decoder: Decoder) throws {
        aboveTokens = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .aboveTokens)
        prices = try TokenPrices(from: decoder)
    }
}

struct ModelPrice: Decodable, Sendable {
    let id, source, lastVerified: String
    let prices: TokenPrices
    let longContext: LongContextPrices?

    enum CodingKeys: String, CodingKey {
        case id, source, lastVerified = "last_verified", longContext = "long_context"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(String.self, forKey: .source)
        lastVerified = try c.decode(String.self, forKey: .lastVerified)
        longContext = try c.decodeIfPresent(LongContextPrices.self, forKey: .longContext)
        prices = try TokenPrices(from: decoder)
    }

    func usd(_ t: TokenCounts) -> Decimal {
        let prompt = t.input + t.cacheRead + t.cacheWrite5m + t.cacheWrite1h
        if let longContext, prompt > longContext.aboveTokens { return longContext.prices.usd(t) }
        return prices.usd(t)
    }
}

enum PriceDataError: Error, Equatable {
    case noModels
    case duplicateID(String)
    case badPrice(String)
    case missingSource(String)
    case badRate
}

/// The contents of `prices.json` (TRD 6).
struct PriceTable: Decodable, Sendable {
    let lastVerified: String
    let usdToEUR: Decimal
    let fxUpdated, fxNote: String
    let models: [ModelPrice]

    enum CodingKeys: String, CodingKey {
        case models
        case lastVerified = "last_verified", usdToEUR = "usd_to_eur", fxUpdated = "fx_updated", fxNote = "fx_note"
    }

    /// Decodes and validates the file. Any error rejects the whole file.
    static func decode(_ json: Data) throws -> PriceTable {
        let table = try JSONDecoder().decode(PriceTable.self, from: json)
        guard table.usdToEUR > 0, !table.fxUpdated.isEmpty, !table.lastVerified.isEmpty else {
            throw PriceDataError.badRate
        }
        guard !table.models.isEmpty else { throw PriceDataError.noModels }
        var seen = Set<String>()
        for model in table.models {
            guard seen.insert(model.id).inserted else { throw PriceDataError.duplicateID(model.id) }
            guard !model.source.isEmpty, !model.lastVerified.isEmpty else { throw PriceDataError.missingSource(model.id) }
            let prices = model.prices.all + (model.longContext?.prices.all ?? [])
            guard prices.allSatisfy({ $0 >= 0 }), (model.longContext?.aboveTokens ?? 1) > 0 else {
                throw PriceDataError.badPrice(model.id)
            }
        }
        return table
    }

    static func shipped() throws -> PriceTable {
        guard let url = Bundle.tokenBar.url(forResource: "prices", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    /// An exact `id` match, else an `id` plus a date suffix, for example `claude-haiku-4-5-20251001` (TRD 6, rule 2).
    /// Only a date suffix matches. Thus `gpt-5.5-pro` does not get the `gpt-5.5` price (rule 3).
    func price(for model: String) -> ModelPrice? {
        models.first { $0.id == model }
            ?? models.first { model.hasPrefix($0.id) && model.dropFirst($0.id.count).wholeMatch(of: /-\d{4}-?\d{2}-?\d{2}/) != nil }
    }

    /// API-equivalent cost in EUR. Nil if the model has no price: do not guess (TRD 6, rules 3 and 6).
    func costEUR(_ record: UsageRecord) -> Decimal? {
        price(for: record.model).map { $0.usd(record.tokens) * usdToEUR }
    }
}

/// Remembers the EUR cost of each record, so a refresh prices only the new records (IES-225).
/// Without it, each refresh priced 35 days of records again: about 0.3 s of CPU.
final class CostCache: @unchecked Sendable {  // used only on the main actor
    private var costs: [UsageRecord: Decimal?] = [:]
    private var prunedDay: Date?

    var count: Int { costs.count }

    func costEUR(_ record: UsageRecord, prices: PriceTable) -> Decimal? {
        if let hit = costs[record] { return hit }
        let cost = prices.costEUR(record)
        costs[record] = cost
        return cost
    }

    /// One time each day, drops the records before `start`. The cache then does not grow without a limit.
    func prune(before start: Date, day: Date) {
        guard prunedDay != day else { return }
        prunedDay = day
        costs = costs.filter { $0.key.timestamp >= start }
    }
}
