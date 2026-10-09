import Foundation
import Observation

/// Holds the last good snapshot of each provider. `AppModel` calls `refresh()` every 60 s (TRD 7).
@MainActor @Observable
final class UsageStore {
    enum Period { case today, week }

    private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    /// Only "cannot read the source" is an error (DRD 2.4). A success clears the error.
    private(set) var errors: [ProviderID: any Error] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    private let providers: [any UsageProvider]
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(providers: [any UsageProvider], calendar: Calendar = .current, now: @escaping @Sendable () -> Date = Date.init) {
        self.providers = providers
        self.calendar = calendar
        self.now = now
    }

    /// Reads the providers at the same time: all, or only `ids`. A failed provider keeps its last snapshot.
    func refresh(only ids: Set<ProviderID>? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let date = now()
        await withTaskGroup(of: (ProviderID, Result<ProviderSnapshot, any Error>).self) { group in
            for provider in providers where ids?.contains(provider.id) ?? true {
                group.addTask {
                    do { return (provider.id, .success(try await provider.fetch(now: date))) }
                    catch { return (provider.id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let snapshot):
                    snapshots[id] = snapshot
                    errors[id] = nil
                case .failure(let error):
                    errors[id] = error
                }
            }
        }
        lastRefresh = date
    }

    /// Today starts at local midnight. Week is the rolling last 7 × 24 h.
    func totals(_ period: Period) -> [ProviderID: [String: TokenCounts]] {
        let date = now()
        let start = period == .today ? calendar.startOfDay(for: date) : date.addingTimeInterval(-7 * 24 * 3600)
        var result: [ProviderID: [String: TokenCounts]] = [:]
        for snapshot in snapshots.values {
            for record in snapshot.records where record.timestamp >= start && record.timestamp <= date {
                result[record.provider, default: [:]][record.model, default: TokenCounts()].add(record.tokens)
            }
        }
        return result
    }
}

private extension TokenCounts {
    mutating func add(_ other: TokenCounts) {
        input += other.input
        output += other.output
        cacheRead += other.cacheRead
        cacheWrite5m += other.cacheWrite5m
        cacheWrite1h += other.cacheWrite1h
    }
}
