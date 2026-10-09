import Foundation

/// The contents of `water.json` (DRD 7.8, D41). The factor is per output token.
/// Coding agents read large caches again and again, so input tokens would make the value meaningless.
struct WaterData: Decodable, Sendable {
    struct Unit: Decodable, Sendable {
        let id, singular, plural: String
        let ml: Double
    }

    let mlPerOutputToken: Double
    let source, lastVerified: String
    let units: [Unit]

    struct Invalid: Error {}

    static func decode(_ json: Data) throws -> WaterData {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try decoder.decode(WaterData.self, from: json)
        guard data.mlPerOutputToken > 0, !data.units.isEmpty, data.units.allSatisfy({ $0.ml > 0 }) else { throw Invalid() }
        return data
    }

    static func shipped() throws -> WaterData {
        guard let url = Bundle.tokenBar.url(forResource: "water", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    func ml(outputTokens: Int) -> Double { Double(outputTokens) * mlPerOutputToken }

    /// The calculation line (D47), for example "195,556 output tokens × 0.1125 mL each (Mistral estimate)".
    func math(outputTokens: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        return "\(f.string(from: outputTokens as NSNumber) ?? "\(outputTokens)") output tokens × \(mlPerOutputToken) mL each (Mistral estimate)"
    }

    /// The unit equivalent in the popover, for example "15 bottles (1.5 L)".
    /// The largest unit with a count of 1 or more, else the smallest unit.
    func equivalent(ml: Double) -> String {
        let sorted = units.sorted { $0.ml < $1.ml }
        let unit = sorted.last { ml / $0.ml >= 1 } ?? sorted[0]
        let count = ml / unit.ml
        let shown = String(format: count < 10 ? "%.1f" : "%.0f", count)
        return "\(shown) \(shown == "1.0" ? unit.singular : unit.plural)"
    }

    /// "450 mL", "2.3 L", "22 L". Fills `{water}`.
    static func amount(_ ml: Double) -> String {
        if ml < 1000 { return String(format: "%.0f mL", ml) }
        let litres = ml / 1000
        return String(format: litres < 10 ? "%.1f L" : "%.0f L", litres)
    }

    /// Fits 52 pt with the water icon (D43): "0.1 L", "9.9 L", "999 L", "1.1kL", "99kL".
    static func barValue(_ ml: Double) -> String {
        let litres = ml / 1000
        return switch litres {
        case ..<9.95: String(format: "%.1f L", max(0.1, litres))
        case ..<999.5: String(format: "%.0f L", litres)
        case ..<9950: String(format: "%.1fkL", litres / 1000)
        default: String(format: "%.0fkL", litres / 1000)
        }
    }
}
