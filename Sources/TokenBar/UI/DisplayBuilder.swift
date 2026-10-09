import Foundation

/// Makes the `DisplaySnapshot` from the store data (TRD-T08, DRD 2 and 3).
/// The roast selector and the tuition total keep state. The caller owns them and passes them in.
struct DisplayBuilder {
    let prices: PriceTable
    let cafe: CafeData
    var defaults = UserDefaults.standard
    var calendar = Calendar.current

    /// The café unit of the day: `["day": Date, "id": String]` (DRD 7.6 rule 4).
    static let cafeUnitKey = "displayCafeUnitOfDay"

    func build(snapshots: [ProviderID: ProviderSnapshot], errors: [ProviderID: any Error], lastRefresh: Date?,
               now: Date, roasts: inout RoastSelector, tuition: TuitionTotal) -> DisplaySnapshot {
        let today = calendar.startOfDay(for: now)
        let weekStart = now.addingTimeInterval(-7 * 24 * 3600)
        let style = defaults.string(forKey: SettingsKey.barStyle).flatMap(BarStyle.init)
        let funny = style == .funny
        let cafeOn = funny && setting(SettingsKey.cafeIndexEnabled)
        let roastsOn = funny && setting(SettingsKey.roastsEnabled)

        // A missing source folder means "not installed". It is not an error (DRD 2.4).
        var rows: [DisplaySnapshot.ProviderRow] = []
        var records: [UsageRecord] = []
        var dailyCosts: [Date: Decimal] = [:]
        var costToday: Decimal = 0, costWeek: Decimal = 0
        for id in ProviderID.allCases {
            let error = errors[id]
            let installed = error.map { !Self.isNotInstalled($0) } ?? (snapshots[id] != nil)
            let snapshot = installed ? snapshots[id] : nil
            var rowCost: Decimal?, unpriced = false
            for record in snapshot?.records ?? [] where record.timestamp <= now {
                records.append(record)
                let cost = prices.costEUR(record)
                if record.timestamp >= weekStart, cost == nil { unpriced = true }
                if record.timestamp >= today {
                    rowCost = (rowCost ?? 0) + (cost ?? 0)
                    costToday += cost ?? 0
                }
                guard let cost else { continue }
                dailyCosts[calendar.startOfDay(for: record.timestamp), default: 0] += cost
                if record.timestamp >= weekStart { costWeek += cost }
            }
            let limits = (snapshot?.limits ?? []).map {
                DisplaySnapshot.Limit(name: $0.name, usedPercent: $0.resetsAt.map { $0 <= now } == true ? 0 : $0.usedPercent,
                                      resetsAt: $0.resetsAt, observedAt: $0.observedAt)
            }
            rows.append(.init(provider: id, installed: installed,
                              errorText: installed && error != nil ? "TokenBar cannot read the \(Self.name(id)) logs. The log format possibly changed." : nil,
                              limits: limits, costTodayEUR: rowCost, hasUnpricedModels: unpriced))
        }

        let installedRows = rows.filter(\.installed)
        let top = Self.topLimit(in: rows)
        let hasData = !records.isEmpty || top != nil
        let percent = top?.limit.usedPercent ?? 0
        let state: DisplaySnapshot.State =
            if installedRows.isEmpty { .noData }
            else if installedRows.allSatisfy({ $0.errorText != nil }) { .error }
            else if !hasData { .noData }
            else if percent >= 100 { .limitHit }
            else if percent >= 80 { .warning }
            else { .normal }

        // One café unit, kept for the day (DRD 7.6).
        var pick: CafeIndex.Pick?
        if cafeOn {
            let stored = defaults.dictionary(forKey: Self.cafeUnitKey)
            let kept = stored?["day"] as? Date == today ? stored?["id"] as? String : nil
            pick = CafeIndex.pick(costEUR: costToday, units: cafe.units, keptID: kept)
            if let pick { defaults.set(["day": today, "id": pick.unit.id], forKey: Self.cafeUnitKey) }
        }
        let spend = hasData ? tuition.update(now: now, dailyCostsEUR: dailyCosts, todayEUR: costToday) : nil

        // Menu bar (DRD 2.4 and 2.5). Both styles show the limit value in Warning and Limit hit.
        let reset = top?.limit.resetsAt.map { Self.shortDuration($0.timeIntervalSince(now)) }
        let (text, symbol): (String, String) = switch state {
        case .noData: ("", "circle.dashed")
        case .error: ("", "exclamationmark.circle")
        case .limitHit: (reset ?? "100%", "hourglass")
        case .warning: ("\(Int(percent))%", "exclamationmark.triangle.fill")
        case .normal:
            if let pick { (Self.barValue(pick.value), pick.unit.symbol) }
            else if let top { ("\(Int(top.limit.usedPercent))%", "circle.lefthalf.filled") }
            else { (Self.shortEUR(costToday), "circle.lefthalf.filled") }
        }

        var roast: String?
        if roastsOn, hasData, state != .error {
            let last = records.max { $0.timestamp < $1.timestamp }
            let first = records.map(\.timestamp).min()
            roast = roasts.roast(for: RoastState(
                now: now, calendar: calendar, percent: top?.limit.usedPercent, limitHit: state == .limitHit,
                lastUsage: last?.timestamp, costEUR: NSDecimalNumber(decimal: costToday).doubleValue,
                providersToday: Set(records.filter { $0.timestamp >= today }.map(\.provider.rawValue)),
                daysOfData: first.flatMap { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: today).day } ?? 0,
                model: last?.model, provider: last.map { Self.name($0.provider) }, reset: reset,
                unitValue: pick?.value, unitPlural: pick?.name,
                tuitionPercent: spend.map { CafeIndex.tuitionPercent(spendEUR: $0, tuition: cafe.tuition) },
                tuitionYears: tuition.years(now: now, dailyCostsEUR: dailyCosts, tuition: cafe.tuition)))
        }

        return DisplaySnapshot(
            state: state, barStyle: style, menuBarText: text, menuBarSymbol: symbol, rows: rows,
            costTodayEUR: costToday, costWeekEUR: costWeek,
            cafeLine: pick.map { "Today = \($0.text)" }, cafeSymbol: pick?.unit.symbol,
            tuitionLine: cafeOn ? spend.map { CafeIndex.tuitionLine(spendEUR: $0, tuition: cafe.tuition) } : nil,
            roast: roast, lastRefresh: lastRefresh, pricesVerified: prices.lastVerified)
    }

    private func setting(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }

    static func isNotInstalled(_ error: any Error) -> Bool {
        if case ClaudeCodeProvider.Failure.notFound = error { return true }
        return (error as? CocoaError)?.code == .fileReadNoSuchFile
    }

    static func name(_ provider: ProviderID) -> String {
        switch provider {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// The highest limit of all providers. A tie goes to the later reset, the longer wait.
    static func topLimit(in rows: [DisplaySnapshot.ProviderRow]) -> (provider: ProviderID, limit: DisplaySnapshot.Limit)? {
        rows.flatMap { row in row.limits.map { (provider: row.provider, limit: $0) } }.max {
            ($0.limit.usedPercent, $0.limit.resetsAt ?? .distantPast) < ($1.limit.usedPercent, $1.limit.resetsAt ?? .distantPast)
        }
    }

    /// Fits 52 pt: "42m", "1h48", "23h", "3d".
    static func shortDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return switch minutes {
        case ..<60: "\(minutes)m"
        case ..<600: "\(minutes / 60)h" + String(format: "%02d", minutes % 60)
        case ..<1440: "\(minutes / 60)h"
        default: "\(minutes / 1440)d"
        }
    }

    /// Fits 52 pt, so it has no "≈": "€3.4", "€12", "€123", "€4k". The limits keep "€10.0" and "€1000" out.
    /// The menu bar has no room for two decimals (52 pt). Below 1, show one decimal, minimum "0.1".
    /// The popover keeps the full value.
    static func barValue(_ value: String) -> String {
        guard let number = Double(value), number < 1 else { return value }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), max(0.1, (number * 10).rounded() / 10))
    }

    static func shortEUR(_ cost: Decimal) -> String {
        if cost >= Decimal(string: "999.5")! { return "€\(NSDecimalNumber(decimal: CafeIndex.rounded(cost / 1000, 0)).intValue)k" }
        let places = cost > 0 && cost < Decimal(string: "9.95")! ? 1 : 0
        return "€" + cost.formatted(.number.precision(.fractionLength(places)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }
}
