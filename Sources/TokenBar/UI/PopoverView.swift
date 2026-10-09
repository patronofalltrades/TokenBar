import AppKit
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
    var actions = PopoverActions()
    /// Fixed time for previews and tests. Nil: the current time, updated each minute.
    var now: Date?
    @State private var listHeight: CGFloat = 0
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
                Divider()
                // DRD 3.1: the list scrolls only when it is taller than its share of the 560 pt.
                if listHeight > 320 {
                    ScrollView { providerListView(now: now) }.frame(height: 320)
                } else {
                    providerListView(now: now)
                }
                Divider()
                totals
                if let roast = snapshot.roast {
                    Divider()
                    Text("“\(roast)”")
                        .font(.callout).italic().foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Roast: \(roast)")
                }
            }
            Divider()
            footer(now: now)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .frame(maxHeight: 560)
        .symbolRenderingMode(.hierarchical)
    }

    private func providerListView(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleRows, id: \.provider) { row in
                ProviderRowView(row: row, now: now, actions: actions)
            }
            if let line = stillAvailableLine { Text(line).font(.callout) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { listHeight = $0 }
    }

    /// "Not installed" rows show only when no provider is installed.
    private var visibleRows: [DisplaySnapshot.ProviderRow] {
        let installed = snapshot.rows.filter(\.installed)
        return installed.isEmpty ? snapshot.rows : installed
    }

    /// DRD 3.5: when one provider hits a limit, name a provider that still has capacity.
    private var stillAvailableLine: String? {
        guard visibleRows.contains(where: \.isLimitHit),
              let other = visibleRows.first(where: { !$0.isLimitHit && $0.errorText == nil && !$0.limits.isEmpty }),
              let top = other.limits.max(by: { $0.usedPercent < $1.usedPercent })
        else { return nil }
        return PopoverFormat.stillAvailable(other.provider, top)
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today \(PopoverFormat.euro(snapshot.costTodayEUR))")
                Spacer()
                Text("Week \(PopoverFormat.euro(snapshot.costWeekEUR))")
            }
            .font(.title3).monospacedDigit()
            if let cafe = snapshot.cafeLine {
                Label(cafe, systemImage: snapshot.cafeSymbol ?? "cup.and.saucer.fill")
                    .font(.callout)
                    .accessibilityLabel("Today's cost, \(PopoverFormat.euro(snapshot.costTodayEUR)), equals \(cafe)")
            }
            if let tuition = snapshot.tuitionLine {
                Label(tuition, systemImage: "graduationcap").font(.callout)
            }
        }
    }

    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                footerButton("Settings", symbol: "gearshape", key: ",", action: actions.openSettings)
                if snapshot.state != .noData {
                    footerButton("Refresh", symbol: "arrow.clockwise", key: "r", action: actions.refresh)
                    // DRD 7.7. No keyboard shortcut in the DRD, so none here.
                    Button(action: share) { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.borderless).help("Share").accessibilityLabel("Share")
                }
                Spacer()
                if let last = snapshot.lastRefresh {
                    Text(PopoverFormat.updated(last, now: now)).foregroundStyle(.secondary)
                }
                footerButton("Quit TokenBar", symbol: "power", key: "q", action: actions.quit)
            }
            if copied {
                Text("Copied. Paste it in your Section chat.").font(.caption2)
            } else {
                Text("Prices verified \(snapshot.pricesVerified)").font(.caption2).foregroundStyle(.tertiary)
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
                    Text(DisplayBuilder.name(row.provider)).font(.headline)
                    Spacer()
                    badge
                }
                if !row.installed {
                    Text("Not installed").font(.caption).foregroundStyle(.secondary)
                } else if let error = row.errorText {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(row.limits, id: \.name) { limit in limitView(limit) }
                    Text(row.costTodayEUR.map { "\(PopoverFormat.euro($0)) today (API-equivalent)" } ?? "No usage today")
                        .monospacedDigit()
                    if row.hasUnpricedModels {
                        Text("Price unknown for some models").font(.caption).foregroundStyle(.secondary)
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
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(PopoverFormat.barColor(limit.usedPercent))
                        .scaleEffect(x: min(max(limit.usedPercent, 0), 100) / 100, anchor: .leading)
                }
                .frame(height: 6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: limit.usedPercent)
            Text("\(Int(limit.usedPercent))% of \(limit.name) limit").monospacedDigit()
            Text(detail(limit)).font(.caption).foregroundStyle(.secondary)
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
        if parts.isEmpty { parts.append(name + ".") }
        if let cost = row.costTodayEUR { parts.append("About \(PopoverFormat.euro(cost, approx: false)) today, API-equivalent.") }
        if row.hasUnpricedModels { parts.append("Price unknown for some models.") }
        return parts.joined(separator: " ")
    }
}

/// DRD 4.2. No API option in v1.
private struct NoDataView: View {
    let check: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to TokenBar").font(.headline)
            Text("TokenBar found no Claude Code or Codex logs on this Mac.")
            VStack(alignment: .leading, spacing: 4) {
                Text("I use Claude Code or Codex").font(.body.weight(.medium))
                Text("Run it one time, then click Check again.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("I use only ChatGPT or Claude.ai").font(.body.weight(.medium))
                Text("TokenBar cannot read web chat usage in v1.").foregroundStyle(.secondary)
            }
            Button("Check again", action: check)
            Text("Your data stays on this Mac.").font(.caption).foregroundStyle(.secondary)
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
        percent >= 100 ? .red : percent >= 80 ? .orange : .accentColor
    }

    /// "≈ €2.10".
    static func euro(_ value: Decimal, approx: Bool = true, locale: Locale = .current) -> String {
        let text = value.formatted(.currency(code: "EUR").locale(locale))
        return approx ? "≈ \(text)" : text
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
              costTodayEUR: error == nil ? 3.90 : nil, hasUnpricedModels: false)
    }

    private static let codex = DisplaySnapshot.ProviderRow(
        provider: .codex, installed: true, errorText: nil,
        limits: [.init(name: "weekly", usedPercent: 18, resetsAt: later(60 * 96), observedAt: ago(10))],
        costTodayEUR: 2.20, hasUnpricedModels: true)

    private static func snapshot(_ state: DisplaySnapshot.State, rows: [DisplaySnapshot.ProviderRow],
                                 style: BarStyle = .funny, roast: String?) -> DisplaySnapshot {
        let funny = style == .funny
        return DisplaySnapshot(
            state: state, barStyle: style, menuBarText: "62%", menuBarSymbol: "gauge.with.dots.needle.33percent",
            rows: rows, costTodayEUR: 6.10, costWeekEUR: 21.80,
            cafeLine: funny ? "Today = 3.4 cafés con leche" : nil, cafeSymbol: funny ? "cup.and.saucer.fill" : nil,
            cafeEmoji: funny ? "☕" : nil,
            tuitionLine: funny ? "0.04% of your MBA tuition, in tokens" : nil,
            roast: funny ? roast : nil, lastRefresh: ago(2), pricesVerified: "2026-10-08")
    }

    static let normal = snapshot(.normal, rows: [claude(62), codex],
                                 roast: "The protagonist has 38% of Opus left and a 9 AM deadline. Discuss.")
    static let warning = snapshot(.warning, rows: [claude(87), codex],
                                  roast: "87% used before lunch. The case writes itself.")
    static let limitHit = snapshot(.limitHit, rows: [claude(100, weekly: 64), codex],
                                   roast: "Limit reached. Time to read the case yourself.")
    static let error = snapshot(.error, rows: [
        claude(0, error: "TokenBar cannot read the Claude Code logs. The log format possibly changed."), codex,
    ], roast: nil)
    static let serious = snapshot(.normal, rows: [claude(62), codex], style: .serious, roast: "unused")
    static let noData = DisplaySnapshot(
        state: .noData, barStyle: nil, menuBarText: "", menuBarSymbol: "cup.and.saucer",
        rows: ProviderID.allCases.map {
            .init(provider: $0, installed: false, errorText: nil, limits: [], costTodayEUR: nil, hasUnpricedModels: false)
        },
        costTodayEUR: 0, costWeekEUR: 0, cafeLine: nil, cafeSymbol: nil, tuitionLine: nil, roast: nil,
        lastRefresh: nil, pricesVerified: "2026-10-08")

    static let all: [(name: String, snapshot: DisplaySnapshot)] = [
        ("normal", normal), ("warning", warning), ("limitHit", limitHit),
        ("noData", noData), ("error", error), ("serious", serious),
    ]
}

#Preview("Normal") { PopoverView(snapshot: PopoverSamples.normal, now: PopoverSamples.now) }
#Preview("Warning") { PopoverView(snapshot: PopoverSamples.warning, now: PopoverSamples.now) }
#Preview("Limit hit") { PopoverView(snapshot: PopoverSamples.limitHit, now: PopoverSamples.now) }
#Preview("No data") { PopoverView(snapshot: PopoverSamples.noData, now: PopoverSamples.now) }
#Preview("Error") { PopoverView(snapshot: PopoverSamples.error, now: PopoverSamples.now) }
#Preview("Serious") { PopoverView(snapshot: PopoverSamples.serious, now: PopoverSamples.now) }
