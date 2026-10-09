import AppKit
import Testing
@testable import TokenBar

/// D43: each index has a custom icon in the resource bundle. This test fails if a file is missing.
@Test(arguments: IndexChoice.allCases)
func eachIndexHasATemplateIcon(index: IndexChoice) throws {
    let icon = try #require(Icon.custom[index], "Resources/Icons/\(index.rawValue).svg is missing")
    #expect(icon.isTemplate)
    #expect(icon.representations.isEmpty == false)
    let image = Icon.image(index.rawValue, pointSize: 13)
    #expect(image.isTemplate)
    #expect(image.size.height == 15)
    #expect(image.size.width == (index == .water ? 11.25 : 15))
}

/// The menu bar image keeps its height: the 15 pt icon is not taller than the 13 pt text line.
@Test func customIconKeepsTheMenuBarHeight() {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    let text = NSAttributedString(string: "3.4", attributes: [.font: font]).size().height
    for index in IndexChoice.allCases {
        #expect(MenuBarLabel.image(symbol: index.rawValue, text: "3.4").size.height == max(15, text))
    }
}

/// A size change on one image does not change the cached icon.
@Test func iconSizeDoesNotChangeTheCache() {
    _ = Icon.image("cafe", pointSize: 30)
    #expect(Icon.custom[.cafe]?.size == NSSize(width: 24, height: 24))
}

/// Other names stay SF Symbols.
@Test func otherNamesAreSFSymbols() {
    #expect(Icon.image("hourglass", pointSize: 13).size.width > 0)
}
