import Foundation

/// Makes the `DisplaySnapshot` from the store data (TRD-T08, DRD 2 and 3).
/// The roast selector and the tuition total keep state. The caller owns them and passes them in.
struct DisplayBuilder {
    let prices: PriceTable
    let cafe: CafeData
    let water: WaterData
    var defaults = UserDefaults.standard
    var calendar = Calendar.current

    /// The café unit of the day: `["day": Date, "id": String]` (DRD 7.6 rule 4).
    static let cafeUnitKey = "displayCafeUnitOfDay"

    func build(snapshots: [ProviderID: ProviderSnapshot], errors: [ProviderID: any Error], lastRefresh: Date?,
               now: Date, roasts: inout RoastSelector, tuition: TuitionTotal) -> DisplaySnapshot {
        let today = calendar.startOfDay(for: now)
        let weekStart = now.addingTimeInterval(-7 * 24 * 3600)
        let index = IndexChoice.saved(in: defaults)
        let roastsOn = index != nil && defaults.object(forKey: SettingsKey.roastsEnabled) as? Bool ?? true

        // A missing source folder means "not installed". It is not an error (DRD 2.4).
        var rows: [DisplaySnapshot.ProviderRow] = []
        var records: [UsageRecord] = []
        var dailyCosts: [Date: Decimal] = [:]
        var costToday: Decimal = 0, costWeek: Decimal = 0, outputToday = 0, outputWeek = 0
        for id in ProviderID.allCases {
            let error = errors[id]
            let installed = error.map { !Self.isNotInstalled($0) } ?? (snapshots[id] != nil)
            let snapshot = installed ? snapshots[id] : nil
            var unpriced = false
            for record in snapshot?.records ?? [] where record.timestamp <= now {
                records.append(record)
                let cost = prices.costEUR(record)
                if record.timestamp >= weekStart {
                    outputWeek += record.tokens.output
                    if cost == nil { unpriced = true }
                }
                if record.timestamp >= today {
                    outputToday += record.tokens.output
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
                              limits: limits, hasUnpricedModels: unpriced))
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

        // One index only (D41). One café unit, kept for the day (DRD 7.6).
        var pick: CafeIndex.Pick?
        if index == .cafe {
            let stored = defaults.dictionary(forKey: Self.cafeUnitKey)
            let kept = stored?["day"] as? Date == today ? stored?["id"] as? String : nil
            pick = CafeIndex.pick(costEUR: costToday, units: cafe.units, keptID: kept)
            if let pick { defaults.set(["day": today, "id": pick.unit.id], forKey: Self.cafeUnitKey) }
        }
        let spend = hasData ? tuition.update(now: now, dailyCostsEUR: dailyCosts, todayEUR: costToday) : nil
        let waterML = index == .water && outputToday > 0 ? water.ml(outputTokens: outputToday) : nil
        let tuitionSpend = index == .tuition ? spend : nil
        // The popover headline and its second line (DRD 3.1). They show also at zero, unlike the menu bar value.
        let line: (text: String, detail: String?, symbol: String, emoji: String)?
        switch hasData ? index : nil {
        case .cafe:
            let day = pick ?? CafeIndex.format(0, unit: cafe.units[0])
            let week = CafeIndex.format(costWeek / day.unit.priceEUR, unit: day.unit)
            line = ("\(day.text) today", "\(week.value) this week", day.unit.symbol, day.unit.emoji)
        case .tuition:
            let first = tuition.defaults.object(forKey: TuitionTotal.firstLaunchKey) as? Date
            line = (CafeIndex.tuitionLine(spendEUR: spend ?? 0, tuition: cafe.tuition),
                    first.flatMap { CafeIndex.burnLine(spendEUR: spend ?? 0, days: now.timeIntervalSince($0) / 86_400,
                                                       tuition: cafe.tuition, year: calendar.component(.year, from: now)) },
                    Self.tuitionSymbol, "🎓")
        case .water:
            let ml = water.ml(outputTokens: outputToday)
            let week = "\(WaterData.amount(water.ml(outputTokens: outputWeek))) this week"
            line = ("\(WaterData.amount(ml)) of water today", ml > 0 ? "\(water.equivalent(ml: ml)) · \(week)" : week,
                    Self.waterSymbol, "💧")
        case nil: line = nil
        }

        // Menu bar (DRD 2.4 and 2.5). Each choice shows the limit value in Warning and Limit hit.
        let reset = top?.limit.resetsAt.map { Self.shortDuration($0.timeIntervalSince(now)) }
        let (text, symbol): (String, String) = switch state {
        case .noData: ("", "circle.dashed")
        case .error: ("", "exclamationmark.circle")
        case .limitHit: (reset ?? "100%", "hourglass")
        case .warning: ("\(Int(percent))%", "exclamationmark.triangle.fill")
        case .normal:
            if let pick { (Self.barValue(pick.value), pick.unit.symbol) }
            else if let tuitionSpend { (CafeIndex.tuitionBarValue(spendEUR: tuitionSpend, tuition: cafe.tuition), Self.tuitionSymbol) }
            else if let waterML { (WaterData.barValue(waterML), Self.waterSymbol) }
            else if let top { ("\(Int(top.limit.usedPercent))%", "circle.lefthalf.filled") }
            else { ("", "circle.lefthalf.filled") }  // no EUR in the menu bar (D42)
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
                tuitionPercent: tuitionSpend.map { CafeIndex.tuitionPercent(spendEUR: $0, tuition: cafe.tuition) },
                tuitionYears: index == .tuition ? tuition.years(now: now, dailyCostsEUR: dailyCosts, tuition: cafe.tuition) : nil,
                water: waterML.map(WaterData.amount)))
        }

        return DisplaySnapshot(
            state: state, index: index, menuBarText: text, menuBarSymbol: symbol, rows: rows,
            indexLine: line?.text, indexSymbol: line?.symbol, indexEmoji: line?.emoji, indexDetail: line?.detail,
            roast: roast, lastRefresh: lastRefresh, pricesVerified: prices.lastVerified)
    }

    static let tuitionSymbol = "graduationcap.fill"
    static let waterSymbol = "drop.fill"

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

    /// The menu bar has no room for two decimals (52 pt). Below 1, show one decimal, minimum "0.1".
    /// The popover keeps the full value.
    static func barValue(_ value: String) -> String {
        guard let number = Double(value), number < 1 else { return value }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), max(0.1, (number * 10).rounded() / 10))
    }

}
