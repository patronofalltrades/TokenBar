import Foundation

/// The three boards (TRD 17.3). The server returns numbers. The app turns them into the unit of the index.
enum LeaderboardRanking {
    struct Entry: Equatable, Sendable {
        let rank: Int
        let handle: String
        let value: Double  // in the unit of the board
        let text: String   // no EUR (D42)
        let isMe: Bool
    }

    /// A higher value ranks first. Equal values rank by handle, so the order does not change between fetches.
    static func entries(_ members: [LeaderboardMember], index: IndexChoice, me: String,
                        cafe: CafeData, water: WaterData) -> [Entry] {
        let unit = cafe.units[0]
        // A member sends any number (TRD 17.5). Keep the server limits: NaN or a huge value must not break the sort or a unit.
        func limit(_ x: Double, _ top: Double) -> Double { x.isFinite ? min(max(x, 0), top) : 0 }
        let scored = members.map { member -> (LeaderboardMember, Double, String) in
            switch index {
            case .cafe:
                let value = limit(member.weekCostEUR, 100_000) / NSDecimalNumber(decimal: unit.priceEUR).doubleValue
                return (member, value, CafeIndex.format(Decimal(value), unit: unit).text)
            case .water:
                let ml = water.ml(outputTokens: min(max(0, member.weekOutputTokens), 10_000_000_000_000))
                return (member, ml, WaterData.amount(ml))
            case .tuition:
                let spend = Decimal(limit(member.spendSinceInstallEUR, 10_000_000))
                return (member, NSDecimalNumber(decimal: spend / cafe.tuition.priceEUR * 100).doubleValue,
                        "\(CafeIndex.tuitionPercent(spendEUR: spend, tuition: cafe.tuition)) of tuition")
            }
        }
        let ordered = scored.sorted {
            $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.handle.lowercased() < $1.0.handle.lowercased()
        }
        return ordered.enumerated().map { offset, item in
            Entry(rank: offset + 1, handle: item.0.handle, value: item.1, text: item.2,
                  isMe: item.0.handle.lowercased() == me.lowercased())
        }
    }
}
