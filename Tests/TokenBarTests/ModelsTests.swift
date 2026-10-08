import Testing
@testable import TokenBar

// Data files and settings store these raw values.
@Test func providerIDRawValuesAreStable() {
    #expect(ProviderID.allCases.map(\.rawValue) == ["claudeCode", "codex"])
}
