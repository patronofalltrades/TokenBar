import Testing
@testable import TokenBar

@Test func appTypeIsVisibleToTests() {
    #expect(String(describing: TokenBarApp.self) == "TokenBarApp")
}
