import AppKit
import Charts
import SwiftUI

/// What the popover buttons do. TRD-T29 connects these to the store and the windows.
struct PopoverActions {
    var refresh: @MainActor () -> Void = {}
    var openSettings: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    var reportProblem: @MainActor () -> Void = { NSWorkspace.shared.open(Links.feedback) }
}

/// The popover (DRD 3 and 4.2). It only reads the snapshot.
struct PopoverView: View {
    let snapshot: DisplaySnapshot
    /// The class leaderboard card (DRD 3.10). Nil hides it.
    var leaderboard: LeaderboardCardData?
    var actions = PopoverActions()
    /// Fixed time for previews and tests. Nil: the current time, updated each minute.
    var now: Date?
    @State private var bodyHeight: CGFloat = 0
    @State private var copied = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: now ?? context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.state == .noData {
                NoDataView(check: actions.refresh)
            } else {
                Text("TokenBar").font(.headline)
                // DRD 3.1: the part between the header and the footer scrolls only when it is taller than `bodyMax`.
                if bodyHeight > Self.bodyMax {
                    ScrollView { bodyContent(now: now) }.scrollIndicators(.visible).frame(height: Self.bodyMax)
                } else {
                    bodyContent(now: now)
                }
            }
            Theme.hairline
            footer(now: now)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .frame(maxHeight: 560)
        .onGlass()
        .symbolRenderingMode(.hierarchical)
    }

    /// 560 pt minus the padding (32), the header (20), the footer with its rule and its confirmation line (about 60)
    /// and the 12 pt gaps between them. The popover is then never taller than 560 pt.
    private static let bodyMax: CGFloat = 400

    /// The headline, the provider rows with the radar, and the roast. This part scrolls as one.
    private func bodyContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            headline
            providerListView(now: now)
            if let leaderboard { LeaderboardCard(data: leaderboard, now: now) }
            if let roast = snapshot.roast {
                Text("“\(roast)”")
                    .font(.callout).italic().foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .glassCard()
                    .accessibilityLabel("Roast: \(roast)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { bodyHeight = $0 }
    }

    private func providerListView(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleRows, id: \.provider) { row in
                ProviderRowView(row: row, now: now, actions: actions)
            }
            if let line = stillAvailableLine { Text(line).font(.callout).glassCard() }
            // A radar with fewer than 3 axes has no area.
            if snapshot.shares.count >= 3, snapshot.shares.contains(where: { $0.percent > 0 }) {
                RadarView(shares: snapshot.shares)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Not installed" rows show only when no provider is installed.
    /// Gemini CLI, Grok Build and Muse Code show only when they are installed: most users do not have them.
    private var visibleRows: [DisplaySnapshot.ProviderRow] {
        let installed = snapshot.rows.filter(\.installed)
        return installed.isEmpty ? snapshot.rows.filter { [.claudeCode, .codex].contains($0.provider) } : installed
    }

    /// DRD 3.5: when one provider hits a limit, name a provider that still has capacity.
    private var stillAvailableLine: String? {
        guard visibleRows.contains(where: \.isLimitHit),
              let other = visibleRows.first(where: { !$0.isLimitHit && $0.errorText == nil && !$0.limits.isEmpty }),
              let top = other.limits.max(by: { $0.usedPercent < $1.usedPercent })
        else { return nil }
        return PopoverFormat.stillAvailable(other.provider, top)
    }

    /// A week without usage has no line to show.
    private var showsTrend: Bool { snapshot.indexLine != nil && snapshot.trend.contains { $0.value > 0 } }

    /// DRD 3.1: the selected index, large, with one small second line. No EUR (D42).
    @ViewBuilder private var headline: some View {
        if let line = snapshot.indexLine {
            VStack(alignment: .leading, spacing: 4) {
                Icon.label(line, icon: snapshot.indexSymbol ?? IndexChoice.cafe.rawValue, style: .title2)
                    .font(.title2.weight(.semibold)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = snapshot.indexDetail {
                    Text(detail).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let math = snapshot.indexMath {
                    Text(math).font(.caption.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                }
                if PopoverFormat.notCounted(snapshot) {
                    Text("Some models not counted").font(.caption2)
                }
                if showsTrend {
                    TrendView(points: snapshot.trend, delta: snapshot.trendDelta)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.paper)  // white on red, or near-black on white
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                footerButton("Settings", symbol: "gearshape", key: ",", action: actions.openSettings)
                if snapshot.state != .noData {
                    footerButton("Refresh", symbol: "arrow.clockwise", key: "r", action: actions.refresh)
                }
                // DRD 7.7. No keyboard shortcut in the DRD, so none here. No card before the index choice.
                if snapshot.state != .noData && snapshot.index != nil {
                    Button(action: share) { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.borderless).help("Share").accessibilityLabel("Share")
                }
                Spacer()
                if let last = snapshot.lastRefresh {
                    Text(PopoverFormat.updated(last, now: now)).foregroundStyle(Theme.secondary)
                }
                footerButton("Quit TokenBar", symbol: "power", key: "q", action: actions.quit)
            }
            if copied {
                Text("Copied. Paste it in your Section chat.").font(.caption2)
            }
        }
        .font(.caption)
    }

    /// The confirmation replaces the prices line for 3 s, so the popover height does not change.
    private func share() {
        guard ShareCard.copy(snapshot) else { return }
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            copied = false
        }
    }

    private func footerButton(_ title: String, symbol: String, key: KeyEquivalent,
                              action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .keyboardShortcut(key)
            .help(title)
            .accessibilityLabel(title)
    }
}

private struct ProviderRowView: View {
    let row: DisplaySnapshot.ProviderRow
    let now: Date
    let actions: PopoverActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let logo = Icon.logo(row.provider, side: 16) { Image(nsImage: logo) }
                    Text(DisplayBuilder.name(row.provider)).font(.headline)
                    Spacer()
                    badge
                }
                if !row.installed {
                    Text("Not installed").font(.caption).foregroundStyle(Theme.secondary)
                } else if let error = row.errorText {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(row.limits, id: \.name) { limit in limitView(limit) }
                    if row.limits.isEmpty { Text("No limit data").font(.caption).foregroundStyle(Theme.secondary) }
                    if let models = row.modelLine {
                        Text("This week: \(models)").font(.caption).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)

            if row.errorText != nil {
                HStack {
                    Button("Try again", action: actions.refresh)
                    Button("Report a problem", action: actions.reportProblem)
                }
            }
        }
        .glassCard()
    }

    @ViewBuilder private var badge: some View {
        if row.errorText != nil {
            Label("Error", systemImage: "info.circle")
        } else if row.isLimitHit {
            Label("Limit hit", systemImage: "hourglass")
        } else if let top = row.topPercent, top >= 80 {
            Label("\(Int(top))%", systemImage: "exclamationmark.triangle.fill").monospacedDigit()
        }
    }

    private func limitView(_ limit: DisplaySnapshot.Limit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // DRD 3.2: the name at the left, the percent at the right, the bar below.
            HStack {
                Text("\(limit.name) limit").fontWeight(.medium)
                Spacer()
                Text("\(Int(limit.usedPercent))%").font(.caption).monospacedDigit()
            }
            Capsule()
                .fill(Theme.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(PopoverFormat.barColor(limit.usedPercent))
                        .scaleEffect(x: min(max(limit.usedPercent, 0), 100) / 100, anchor: .leading)
                }
                .frame(height: 6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: limit.usedPercent)
            Text(detail(limit)).font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    private func detail(_ limit: DisplaySnapshot.Limit) -> String {
        var parts: [String] = []
        if let reset = limit.resetsAt {
            var text = PopoverFormat.reset(reset, now: now)
            if limit.usedPercent >= 100 { text += " (at \(PopoverFormat.time(reset)))" }
            parts.append(text)
        }
        parts.append("as of \(PopoverFormat.time(limit.observedAt))")
        return parts.joined(separator: " · ")
    }

    /// DRD 9.1: one element per row.
    private var accessibilityText: String {
        let name = DisplayBuilder.name(row.provider)
        guard row.installed else { return "\(name), not installed." }
        if let error = row.errorText { return "\(name), error. \(error)" }
        var parts = row.limits.map { limit in
            var text = "\(name) \(limit.name) limit, \(Int(limit.usedPercent)) percent used"
            if let reset = limit.resetsAt { text += ", \(PopoverFormat.reset(reset, now: now, spoken: true))" }
            return text + ". As of \(PopoverFormat.time(limit.observedAt))."
        }
        if parts.isEmpty { parts.append("\(name), no limit data.") }
        if let models = row.modelLine { parts.append("Models this week: \(models).") }
        return parts.joined(separator: " ")
    }
}

/// The sparkline in the index headline (DRD 3.1): the last 7 days or the last 30 days.
/// The pointer on a day shows the day and its value.
/// It has no animation (DRD 8.4).
private struct TrendView: View {
    let points: [DisplaySnapshot.TrendPoint]
    let delta: Int?
    @State private var pointer: Date?
    @AppStorage(SettingsKey.trendDays) private var days = 7

    private var shown: [DisplaySnapshot.TrendPoint] { Array(points.suffix(days == 30 ? 30 : 7)) }
    private var title: String { days == 30 ? "Last 30 days" : "Last 7 days" }

    /// The day nearest to the pointer.
    private var active: DisplaySnapshot.TrendPoint? {
        guard let pointer else { return nil }
        return shown.min { abs($0.day.timeIntervalSince(pointer)) < abs($1.day.timeIntervalSince(pointer)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // One line (D61): a long unit name must not make the headline taller while the pointer moves.
                Text(active.map { "\(PopoverFormat.day($0.day)): \($0.text)" } ?? title)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Button(days == 30 ? "7 days" : "30 days") { days = days == 30 ? 7 : 30 }
                    .buttonStyle(.plain).underline().fixedSize()
                    .accessibilityLabel(days == 30 ? "Show the last 7 days" : "Show the last 30 days")
                // The change compares 7 days with the 7 days before. The 30-day view has no period before it.
                if let delta, days != 30 {
                    Text(PopoverFormat.delta(delta))
                        .padding(.horizontal, 6).padding(.vertical, 1).fixedSize()
                        .background(Color.black.opacity(0.2), in: Capsule())  // dark on the headline: 4.5:1 or more in both modes
                        .help("Against the 7 days before")
                        .accessibilityLabel(PopoverFormat.delta(delta, spoken: true))
                }
            }
            .font(.caption.monospacedDigit())
            Chart(shown, id: \.day) { point in
                AreaMark(x: .value("Day", point.day), y: .value("Value", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [Theme.paper.opacity(0.3), Theme.paper.opacity(0)],
                                                     startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
                LineMark(x: .value("Day", point.day), y: .value("Value", point.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.paper)
                    .accessibilityLabel(PopoverFormat.day(point.day))
                    .accessibilityValue(point.text)
                // The dot is on the pointer day, else on today.
                if point.day == (active ?? shown.last)?.day {
                    PointMark(x: .value("Day", point.day), y: .value("Value", point.value))
                        .symbolSize(40)
                        .foregroundStyle(Theme.paper)
                        .accessibilityHidden(true)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartXSelection(value: $pointer)
            .frame(height: 32)
            .accessibilityLabel(title)
        }
        .padding(.top, 4)
    }
}

/// The provider radar (DRD 3.2): one axis for each installed provider. The most used provider reaches the outer ring.
private struct RadarView: View {
    let shares: [DisplaySnapshot.ProviderShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Most used, last 7 days").font(.caption).foregroundStyle(Theme.secondary)
            GeometryReader { proxy in
                let top = shares.map(\.percent).max() ?? 0
                ZStack {
                    ForEach([1.0 / 3, 2.0 / 3, 1.0], id: \.self) { ring in
                        polygon(in: proxy.size) { _ in ring }.stroke(Theme.rule)
                    }
                    polygon(in: proxy.size) { top > 0 ? shares[$0].percent / top : 0 }.fill(Theme.bar.opacity(0.4))
                    polygon(in: proxy.size) { top > 0 ? shares[$0].percent / top : 0 }.stroke(Theme.ink, lineWidth: 2)
                    ForEach(Array(shares.enumerated()), id: \.element.provider) { index, share in
                        let label = RadarLayout.label(index, count: shares.count, in: proxy.size)
                        Text("\(DisplayBuilder.name(share.provider)) \(Int(share.percent.rounded()))%")
                            .font(.caption2).monospacedDigit().lineLimit(1)
                            .frame(width: label.frame.width, height: label.frame.height,
                                   alignment: label.side == .leading ? .leading : label.side == .trailing ? .trailing : .center)
                            .position(x: label.frame.midX, y: label.frame.midY)
                    }
                }
            }
            .frame(height: 130)
        }
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PopoverFormat.shares(shares))
    }

    private func polygon(in size: CGSize, scale: (Int) -> Double) -> Path {
        Path { path in
            path.addLines(shares.indices.map { RadarLayout.point($0, count: shares.count, scale: scale($0), in: size) })
            path.closeSubpath()
        }
    }
}

/// The class leaderboard card (DRD 3.10): your rank on the board of the selected index, and the top 3.
private struct LeaderboardCard: View {
    let data: LeaderboardCardData
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Class leaderboard").font(.caption.weight(.semibold))
                Spacer()
                Text(data.code).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            if let headline = data.headline, let me = data.me {
                Text("\(headline) · \(me.text)").font(.callout.weight(.medium))
            }
            ForEach(data.top, id: \.rank) { entry in
                HStack {
                    Text("#\(entry.rank)").monospacedDigit()
                    Text(entry.handle).lineLimit(1)
                    Spacer()
                    Text(entry.text).lineLimit(1)
                }
                .font(.caption)
                .fontWeight(entry.isMe ? .medium : .regular)
                .foregroundStyle(entry.isMe ? Theme.ink : Theme.secondary)
            }
            Text(PopoverFormat.updated(data.updatedAt, now: now)).font(.caption2).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.voiceOver)
    }
}

/// DRD 4.2. No API option in v1.
private struct NoDataView: View {
    let check: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to TokenBar").font(.headline)
            Text("TokenBar found no Claude Code, Codex or Gemini CLI logs on this Mac.")
            VStack(alignment: .leading, spacing: 4) {
                Text("I use Claude Code, Codex or Gemini CLI").font(.body.weight(.medium))
                Text("Run it one time, then click Check again.").foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("I use only ChatGPT or Claude.ai").font(.body.weight(.medium))
                Text("TokenBar cannot read web chat usage in v1.").foregroundStyle(Theme.secondary)
            }
            Button("Check again", action: check)
            Text("Your data stays on this Mac.").font(.caption).foregroundStyle(Theme.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension DisplaySnapshot.ProviderRow {
    var topPercent: Double? { limits.map(\.usedPercent).max() }
    var isLimitHit: Bool { (topPercent ?? 0) >= 100 }
}

/// Small text helpers. Tests pass a fixed locale and time zone.
enum PopoverFormat {
    /// DRD 8.1.
    static func barColor(_ percent: Double) -> Color {
        percent >= 80 ? Theme.high : Theme.bar
    }

    /// The footnote under the headline. The Water Footprint counts tokens, not prices, so it has none.
    static func notCounted(_ s: DisplaySnapshot) -> Bool {
        s.index != .water && s.rows.contains(where: \.hasUnpricedModels)
    }

    /// "14:02" in the user's locale.
    static func time(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    /// DRD 3.2: "resets in 1 h 48 min" below 24 hours, else "resets Mon 09:00".
    static func reset(_ date: Date, now: Date, spoken: Bool = false,
                      locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        guard seconds < 24 * 3600 else {
            let style = Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(spoken ? .wide : .abbreviated)
            return "resets \(date.formatted(style)) \(time(date, locale: locale, timeZone: timeZone))"
        }
        let minutes = Int(seconds / 60)
        if spoken {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.allowedUnits = [.hour, .minute]
            var calendar = Calendar.current
            calendar.locale = locale
            formatter.calendar = calendar
            return "resets in \(formatter.string(from: TimeInterval(minutes * 60)) ?? "")"
        }
        let (h, m) = (minutes / 60, minutes % 60)
        return h == 0 ? "resets in \(m) min" : "resets in \(h) h \(m) min"
    }

    /// DRD 3.5: "Codex still available: 82% left this week".
    static func stillAvailable(_ provider: ProviderID, _ limit: DisplaySnapshot.Limit) -> String {
        let window = limit.name == "weekly" ? "this week" : "in this \(limit.name) window"
        return "\(DisplayBuilder.name(provider)) still available: \(100 - Int(limit.usedPercent))% left \(window)"
    }

    /// "Tue 6 Oct" in the user's locale.
    static func day(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The change pill: "▲ 12%", "▼ 8%", "0%". The arrow tells the direction, not a color (DRD 9.3).
    static func delta(_ percent: Int, spoken: Bool = false) -> String {
        if spoken {
            let direction = percent > 0 ? "Up" : percent < 0 ? "Down" : "No change,"
            return "\(direction) \(abs(percent)) percent against the 7 days before"
        }
        return (percent > 0 ? "▲ " : percent < 0 ? "▼ " : "") + "\(abs(percent))%"
    }

    /// The VoiceOver text of the radar: "Output tokens in the last 7 days: Claude Code 60 percent, Codex 30 percent."
    static func shares(_ shares: [DisplaySnapshot.ProviderShare]) -> String {
        "Output tokens in the last 7 days: "
            + shares.map { "\(DisplayBuilder.name($0.provider)) \(Int($0.percent.rounded())) percent" }.joined(separator: ", ") + "."
    }

    /// "Updated 2 min ago".
    static func updated(_ date: Date, now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        switch minutes {
        case 0: return "Updated just now"
        case ..<60: return "Updated \(minutes) min ago"
        default: return "Updated \(minutes / 60) h ago"
        }
    }
}

// MARK: - Samples for previews and tests

enum PopoverSamples {
    /// Sunday 2026-10-11 14:05 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_727_500)

    private static func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
    private static func later(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }

    private static func claude(_ fiveHour: Double, weekly: Double = 24, error: String? = nil) -> DisplaySnapshot.ProviderRow {
        .init(provider: .claudeCode, installed: true, errorText: error,
              limits: error == nil ? [
                  .init(name: "5-hour", usedPercent: fiveHour, resetsAt: later(108), observedAt: ago(3)),
                  .init(name: "weekly", usedPercent: weekly, resetsAt: later(60 * 67), observedAt: ago(3)),
              ] : [],
              hasUnpricedModels: false, modelLine: error == nil ? "claude-opus-4-7 82% · claude-haiku-4-5 18%" : nil)
    }

    private static let codex = DisplaySnapshot.ProviderRow(
        provider: .codex, installed: true, errorText: nil,
        limits: [.init(name: "weekly", usedPercent: 18, resetsAt: later(60 * 96), observedAt: ago(10))],
        hasUnpricedModels: true)

    private static let cafeData = try! CafeData.shipped()  // the shipped file has a test
    private static let sampleUnit = cafeData.units.first { $0.id == "cafe_con_leche" }!
    private static let sampleTuition = cafeData.tuition

    /// The headline, the second line, the calculation and the menu bar value of each choice, for the samples.
    private static let lines: [IndexChoice: (line: String, detail: String, math: String, symbol: String, emoji: String, bar: String)] = [
        .cafe: ("3.4 cafés con leche today", "12 this week", CafeIndex.cafeMath(costEUR: Decimal(string: "6.12")!, unit: sampleUnit), "cafe", "☕", "3.4"),
        .tuition: ("0.04% of your MBA tuition, in tokens", "At this pace, you'll burn through it by the year 4210.",
                   CafeIndex.tuitionMath(spendEUR: Decimal(string: "45.60")!, tuition: sampleTuition),
                   "tuition", "🎓", "0.04%"),
        .water: ("22 L of water today", "15 bottles (1.5 L) · 98 L this week",
                 "195,556 output tokens × 0.1125 mL each (Mistral estimate)", "water", "💧", "22 L"),
    ]

    private static func snapshot(_ state: DisplaySnapshot.State, rows: [DisplaySnapshot.ProviderRow],
                                 index: IndexChoice = .cafe, roast: String?) -> DisplaySnapshot {
        let line = lines[index]
        let trend = [1.2, 2.8, 0, 4.1, 2.2, 5.0, 3.4].enumerated().map { i, value in
            DisplaySnapshot.TrendPoint(day: ago(Double(6 - i) * 1440), value: value, text: "\(value) units")
        }
        return DisplaySnapshot(
            state: state, index: index, menuBarText: line?.bar ?? "62%", menuBarSymbol: line?.symbol ?? "circle.lefthalf.filled",
            rows: rows, indexLine: line?.line, indexSymbol: line?.symbol, indexEmoji: line?.emoji, indexDetail: line?.detail,
            indexMath: line?.math, trend: trend, trendDelta: 12, roast: roast, lastRefresh: ago(2))
    }

    static let normal = snapshot(.normal, rows: [claude(62), codex],
                                 roast: "The protagonist has 38% of Opus left and a 9 AM deadline. Discuss.")
    static let tuition = snapshot(.normal, rows: [claude(62), codex], index: .tuition,
                                  roast: "Your finance professor would call this a sunk cost. Your AI calls it a Tuesday.")
    static let water = snapshot(.normal, rows: [claude(62), codex], index: .water,
                                roast: "Your prompts drank 22 L of water today. Somewhere a cooling tower is writing its own case study.")
    /// Three installed providers, so the radar shows.
    static let radar: DisplaySnapshot = {
        let gemini = DisplaySnapshot.ProviderRow(provider: .geminiCLI, installed: true, errorText: nil, limits: [], hasUnpricedModels: false)
        var s = snapshot(.normal, rows: [claude(62), codex, gemini], roast: nil)
        s.shares = [.init(provider: .claudeCode, percent: 60), .init(provider: .codex, percent: 30), .init(provider: .geminiCLI, percent: 10)]
        return s
    }()
    static let warning = snapshot(.warning, rows: [claude(87), codex],
                                  roast: "87% used before lunch. The case writes itself.")
    static let tuitionWarning = snapshot(.warning, rows: [claude(87), codex], index: .tuition,
                                         roast: "87% used before lunch. The case writes itself.")
    static let waterWarning = snapshot(.warning, rows: [claude(87), codex], index: .water,
                                       roast: "87% used before lunch. The case writes itself.")
    static let limitHit = snapshot(.limitHit, rows: [claude(100, weekly: 64), codex],
                                   roast: "Limit reached. Time to read the case yourself.")
    static let error = snapshot(.error, rows: [
        claude(0, error: "TokenBar cannot read the Claude Code logs. The log format possibly changed."), codex,
    ], roast: nil)
    static let noData = DisplaySnapshot(
        state: .noData, index: nil, menuBarText: "", menuBarSymbol: "cup.and.saucer",
        rows: ProviderID.allCases.map {
            .init(provider: $0, installed: false, errorText: nil, limits: [], hasUnpricedModels: false)
        },
        indexLine: nil, indexSymbol: nil, roast: nil,
        lastRefresh: nil)

    static let all: [(name: String, snapshot: DisplaySnapshot)] = [
        ("cafe", normal), ("tuition", tuition), ("water", water),
        ("warning", warning), ("tuitionWarning", tuitionWarning), ("waterWarning", waterWarning), ("limitHit", limitHit), ("noData", noData), ("error", error), ("radar", radar),
    ]
}

#Preview("Café") { PopoverView(snapshot: PopoverSamples.normal, now: PopoverSamples.now) }
#Preview("Warning") { PopoverView(snapshot: PopoverSamples.warning, now: PopoverSamples.now) }
#Preview("Limit hit") { PopoverView(snapshot: PopoverSamples.limitHit, now: PopoverSamples.now) }
#Preview("No data") { PopoverView(snapshot: PopoverSamples.noData, now: PopoverSamples.now) }
#Preview("Error") { PopoverView(snapshot: PopoverSamples.error, now: PopoverSamples.now) }
#Preview("Tuition") { PopoverView(snapshot: PopoverSamples.tuition, now: PopoverSamples.now) }
#Preview("Water") { PopoverView(snapshot: PopoverSamples.water, now: PopoverSamples.now) }
