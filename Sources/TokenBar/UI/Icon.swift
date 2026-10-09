import AppKit
import SwiftUI

/// The icons of TokenBar (DRD 8.3). An icon name is an `IndexChoice` raw value or an SF Symbol name.
/// The three indexes have custom icons in `Resources/Icons` (D43). All other states use SF Symbols.
enum Icon {
    /// The custom icons, loaded one time. A missing file gives no entry. A test checks all three.
    nonisolated static let custom: [IndexChoice: NSImage] = Dictionary(uniqueKeysWithValues: IndexChoice.allCases.compactMap { index in
        guard let url = Bundle.tokenBar.url(forResource: index.rawValue, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return (index, image)
    })

    /// A template image for a font of `pointSize`. A custom icon is 15/13 of the font size high:
    /// at 13 pt (menu bar) its ink height is 13 to 14 pt, the same as `cup.and.saucer.fill` and `drop.fill`.
    /// The width keeps the aspect ratio of the SVG. `water.svg` has a narrow view box, so "999 L" fits in 52 pt.
    nonisolated static func image(_ name: String, pointSize: CGFloat) -> NSImage {
        guard let index = IndexChoice(rawValue: name) else {
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular)) ?? NSImage()
        }
        guard let image = custom[index]?.copy() as? NSImage else { return NSImage() }  // a copy keeps the cached size
        let height = pointSize * 15 / 13
        image.size = NSSize(width: height * image.size.width / image.size.height, height: height)
        return image
    }

    /// A `Label` with the icon at the size of `style`. An SF Symbol keeps the normal `Label` behavior.
    @ViewBuilder static func label(_ text: String, icon name: String, style: NSFont.TextStyle) -> some View {
        if IndexChoice(rawValue: name) == nil {
            Label(text, systemImage: name)
        } else {
            Label { Text(text) } icon: { Image(nsImage: image(name, pointSize: NSFont.preferredFont(forTextStyle: style).pointSize)) }
        }
    }
}
