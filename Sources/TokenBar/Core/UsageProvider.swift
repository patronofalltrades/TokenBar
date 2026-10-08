import Foundation

/// Each usage source is a provider. A provider returns data only. It does not format text or show UI.
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch(now: Date) async throws -> ProviderSnapshot
}
