import Foundation

extension Bundle {
    /// TokenBar resources. In TokenBar.app the SwiftPM bundle is in Contents/Resources.
    /// The generated `Bundle.module` does not look there, so check it first.
    static var tokenBar: Bundle {
        Bundle.main.url(forResource: "TokenBar_TokenBar", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? .module
    }
}
