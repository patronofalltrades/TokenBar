import AppKit
import SwiftUI

/// The TokenBar visual identity: an espresso-and-cream café palette (DRD 7.9).
/// The menu bar item stays a monochrome template (DRD 2.2).
enum Theme {
    /// Crema amber. The one brand accent: bars, selection, buttons.
    static let accent = Color(red: 0.72, green: 0.48, blue: 0.17)
    /// Warm orange for the warning state (DRD 8.1).
    static let warning = Color(red: 0.88, green: 0.49, blue: 0.18)
    /// Deep red for the limit state (DRD 8.1).
    static let danger = Color(red: 0.79, green: 0.26, blue: 0.18)

    /// Warm paper. Light cream in light mode, deep espresso in dark mode.
    static let paper = dynamic(light: NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.90, alpha: 1),
                               dark: NSColor(calibratedRed: 0.13, green: 0.09, blue: 0.06, alpha: 1))
    /// Espresso ink for text on paper.
    static let ink = dynamic(light: NSColor(calibratedRed: 0.13, green: 0.08, blue: 0.06, alpha: 1),
                             dark: NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.90, alpha: 1))
    /// Latte hairline and quiet surfaces.
    static let latte = dynamic(light: NSColor(calibratedRed: 0.89, green: 0.84, blue: 0.75, alpha: 1),
                               dark: NSColor(calibratedRed: 0.26, green: 0.18, blue: 0.13, alpha: 1))
    /// Fixed cream, for the share card (DRD 7.7, light only).
    static let cream = Color(red: 0.97, green: 0.94, blue: 0.90)

    /// A one-point latte rule between popover sections.
    static var hairline: some View { Rectangle().fill(latte).frame(height: 1) }

    /// A dashed receipt rule, for the share card.
    static var dashed: some View {
        GeometryReader { proxy in
            Path { $0.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                $0.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2)) }
                .stroke(ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 1)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
