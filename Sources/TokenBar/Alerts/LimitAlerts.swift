import Foundation
import UserNotifications

/// Limit alerts: 95% and limit hit (DRD 6, PRD-US-12).
/// Call `refreshed(_:now:)` after each refresh. It sends a maximum of one notification for each call.
struct LimitAlerts {
    enum Event: Int, Codable, Sendable { case warning95 = 1, limitHit = 2 }

    struct Alert: Equatable, Sendable {
        let key: String         // provider + window name + resetsAt + event
        let event: Event
        let title: String
        let body: String
        let expiresAt: Date     // the window reset. After this time the key cannot occur again.
    }

    /// One sent alert. Stored in UserDefaults, so a restart does not send it again.
    struct Sent: Codable, Equatable, Sendable {
        let key: String
        let event: Event
        let sentAt: Date
        let expiresAt: Date
    }

    struct Settings: Sendable {
        var alert95 = true
        var alertLimit = true
        var roasts = true
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The alerts already sent in live windows, oldest first.
    var sent: [Sent] {
        get { defaults.data(forKey: "limitAlertsSent").flatMap { try? JSONDecoder().decode([Sent].self, from: $0) } ?? [] }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "limitAlertsSent") }
    }

    /// Call after each refresh. Sends the due alert, if there is one.
    func refreshed(_ snapshot: DisplaySnapshot, now: Date = Date()) {
        guard let alert = due(snapshot, now: now) else { return }
        Task { await Self.post(alert) }
    }

    /// Returns the alert to send now and records it as sent. Removes the records of reset windows.
    func due(_ snapshot: DisplaySnapshot, now: Date) -> Alert? {
        // Keep a reset record for one hour more, because the 3-in-60-minutes cap counts it.
        var sent = self.sent.filter { $0.expiresAt > now || now.timeIntervalSince($0.sentAt) < 3600 }
        let alert = Self.evaluate(snapshot, now: now, settings: Settings(defaults), sent: sent)
        if let alert { sent.append(Sent(key: alert.key, event: alert.event, sentAt: now, expiresAt: alert.expiresAt)) }
        self.sent = sent
        return alert
    }

    /// Pure rules of DRD 6.1 and 6.2. Returns the most severe alert to send now, or nil.
    static func evaluate(_ snapshot: DisplaySnapshot, now: Date, settings: Settings, sent: [Sent]) -> Alert? {
        // DRD 6.2 rule 2: a maximum of 3 notifications in 60 minutes.
        guard sent.filter({ now.timeIntervalSince($0.sentAt) < 3600 }).count < 3 else { return nil }
        let roast = snapshot.barStyle == .funny && settings.roasts ? snapshot.roast : nil

        let candidates = snapshot.rows.flatMap { row in
            row.limits.compactMap { limit -> Alert? in
                guard now.timeIntervalSince(limit.observedAt) <= 15 * 60 else { return nil }  // DRD 6.2 rule 4
                let event: Event
                if limit.usedPercent >= 100, settings.alertLimit { event = .limitHit }
                else if limit.usedPercent >= 95, settings.alert95 { event = .warning95 }
                else { return nil }

                let window = limit.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
                let key = "\(row.provider.rawValue)|\(limit.name)|\(window)|\(event.rawValue)"
                // DRD 6.2 rules 1 and 3: once in each window, and only the more severe event in 5 minutes.
                guard !sent.contains(where: { $0.key == key }),
                      !sent.contains(where: { now.timeIntervalSince($0.sentAt) < 5 * 60 && $0.event.rawValue >= event.rawValue })
                else { return nil }

                let name = row.provider == .claudeCode ? "Claude Code" : "Codex"
                let title: String, number: String
                switch event {
                case .warning95:
                    title = "\(name): \(Int(limit.usedPercent))% of \(limit.name) limit"
                    number = limit.resetsAt.map { "Resets in \(duration($0.timeIntervalSince(now)))." } ?? "Reset time unknown."
                case .limitHit:
                    title = "\(name): limit reached"
                    number = limit.resetsAt.map { "Resets at \($0.formatted(date: .omitted, time: .shortened))." }
                        ?? "Reset time unknown."
                }
                // ponytail: a window without resetsAt expires after 7 days, the longest known window.
                return Alert(key: key, event: event, title: title, body: [number, roast].compactMap { $0 }.joined(separator: " "),
                             expiresAt: limit.resetsAt ?? now.addingTimeInterval(7 * 24 * 3600))
            }
        }
        return candidates.max { $0.event.rawValue < $1.event.rawValue }
    }

    /// "38 min" or "1h48", like the menu bar.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        return minutes < 60 ? "\(minutes) min" : String(format: "%dh%02d", minutes / 60, minutes % 60)
    }

    /// Asks for permission at the first alert, not at launch (DRD 4.4). Later calls do not show a prompt.
    static func post(_ alert: Alert) async {
        // UNUserNotificationCenter crashes without an app bundle, for example in `swift test` or `swift run`.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.interruptionLevel = .active  // DRD 6.1. Never Time Sensitive.
        try? await center.add(UNNotificationRequest(identifier: alert.key, content: content, trigger: nil))
    }
}

extension LimitAlerts.Settings {
    /// A missing key means on (SettingsKey defaults).
    init(_ defaults: UserDefaults) {
        func on(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        self.init(alert95: on(SettingsKey.alert95Enabled), alertLimit: on(SettingsKey.alertLimitEnabled),
                  roasts: on(SettingsKey.roastsEnabled))
    }
}
