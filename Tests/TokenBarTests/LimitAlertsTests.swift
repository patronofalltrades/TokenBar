import Foundation
import Testing
@testable import TokenBar

private let t0 = Date(timeIntervalSince1970: 1_791_453_600)
private let reset = t0.addingTimeInterval(38 * 60)

private func limit(_ percent: Double, name: String = "5-hour", resetsAt: Date? = reset, observed: Date = t0) -> DisplaySnapshot.Limit {
    .init(name: name, usedPercent: percent, resetsAt: resetsAt, observedAt: observed)
}

private func snapshot(_ limits: [DisplaySnapshot.Limit], style: BarStyle? = .funny, roast: String? = "Discuss.") -> DisplaySnapshot {
    let row = DisplaySnapshot.ProviderRow(provider: .claudeCode, installed: true, errorText: nil, limits: limits,
                                          costTodayEUR: nil, hasUnpricedModels: false)
    return DisplaySnapshot(state: .warning, barStyle: style, menuBarText: "", menuBarSymbol: "", rows: [row],
                           costTodayEUR: 0, costWeekEUR: 0, cafeLine: nil, tuitionLine: nil, roast: roast,
                           lastRefresh: t0, pricesVerified: "")
}

/// Runs a test with a fresh `UserDefaults` suite, so tests do not share the sent-alert record.
private func withAlerts(_ body: (UserDefaults) -> Void) {
    let name = "LimitAlertsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    body(defaults)
}

@Test func warningFiresOnceInEachWindow() {
    withAlerts { defaults in
        let alerts = LimitAlerts(defaults: defaults)
        let alert = alerts.due(snapshot([limit(96)]), now: t0)
        #expect(alert?.event == .warning95)
        #expect(alert?.title == "Claude Code: 96% of 5-hour limit")
        #expect(alert?.body == "Resets in 38 min. Discuss.")
        #expect(alerts.due(snapshot([limit(97, observed: t0 + 600)]), now: t0 + 600) == nil)
    }
}

@Test func limitHitSupersedesWarningInFiveMinutes() {
    withAlerts { defaults in
        let alerts = LimitAlerts(defaults: defaults)
        // Both limits cross in the same refresh: send only the more severe event.
        let both = alerts.due(snapshot([limit(96, name: "weekly"), limit(100)]), now: t0)
        #expect(both?.event == .limitHit)
        #expect(both?.title == "Claude Code: limit reached")
        // A less severe event in the next 5 minutes does not fire.
        #expect(alerts.due(snapshot([limit(96, name: "weekly", observed: t0 + 120)]), now: t0 + 120) == nil)
    }
    withAlerts { defaults in
        let alerts = LimitAlerts(defaults: defaults)
        #expect(alerts.due(snapshot([limit(95)]), now: t0)?.event == .warning95)
        #expect(alerts.due(snapshot([limit(100, observed: t0 + 120)]), now: t0 + 120)?.event == .limitHit)
        #expect(alerts.due(snapshot([limit(100, observed: t0 + 600)]), now: t0 + 600) == nil)
    }
}

@Test func newWindowFiresAgain() {
    withAlerts { defaults in
        let alerts = LimitAlerts(defaults: defaults)
        #expect(alerts.due(snapshot([limit(96)]), now: t0) != nil)
        let later = t0 + 6 * 3600, next = later.addingTimeInterval(3600)
        #expect(alerts.due(snapshot([limit(96, resetsAt: next, observed: later)]), now: later) != nil)
    }
}

@Test func maximumThreeInOneHour() {
    withAlerts { defaults in
        let alerts = LimitAlerts(defaults: defaults)
        for i in 0..<3 {
            let now = t0 + Double(i) * 600
            #expect(alerts.due(snapshot([limit(96, name: "w\(i)", observed: now)]), now: now) != nil)
        }
        let now = t0 + 1800
        #expect(alerts.due(snapshot([limit(96, name: "w3", observed: now)]), now: now) == nil)
        let hourLater = t0 + 3601
        #expect(alerts.due(snapshot([limit(96, name: "w3", resetsAt: nil, observed: hourLater)]), now: hourLater) != nil)
    }
}

@Test func oldDataDoesNotFire() {
    withAlerts { defaults in
        let alerts = LimitAlerts(defaults: defaults)
        #expect(alerts.due(snapshot([limit(100, observed: t0 - 16 * 60)]), now: t0) == nil)
    }
}

@Test func togglesTurnOffEachAlert() {
    withAlerts { defaults in
        defaults.set(false, forKey: SettingsKey.alert95Enabled)
        let alerts = LimitAlerts(defaults: defaults)
        #expect(alerts.due(snapshot([limit(96)]), now: t0) == nil)
        defaults.set(false, forKey: SettingsKey.alertLimitEnabled)
        #expect(alerts.due(snapshot([limit(100)]), now: t0) == nil)
        defaults.set(true, forKey: SettingsKey.alert95Enabled)
        #expect(alerts.due(snapshot([limit(100)]), now: t0)?.event == .warning95)
    }
}

@Test func seriousAndRoastsOffHaveNoRoast() {
    let serious = LimitAlerts.evaluate(snapshot([limit(96)], style: .serious), now: t0, settings: .init(), sent: [])
    #expect(serious?.body == "Resets in 38 min.")
    let off = LimitAlerts.evaluate(snapshot([limit(96)]), now: t0, settings: .init(roasts: false), sent: [])
    #expect(off?.body == "Resets in 38 min.")
}

@Test func recordSurvivesNewInstance() {
    withAlerts { defaults in
        #expect(LimitAlerts(defaults: defaults).due(snapshot([limit(96)]), now: t0) != nil)
        let restarted = LimitAlerts(defaults: defaults)
        #expect(restarted.sent.count == 1)
        #expect(restarted.due(snapshot([limit(96, observed: t0 + 1200)]), now: t0 + 1200) == nil)
        // After the reset and the cap hour, the record is removed.
        _ = restarted.due(snapshot([]), now: reset + 3600)
        #expect(restarted.sent.isEmpty)
    }
}

@Test func durationFormat() {
    #expect(LimitAlerts.duration(38 * 60) == "38 min")
    #expect(LimitAlerts.duration(108 * 60) == "1h48")
}
