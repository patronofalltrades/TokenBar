import AppKit
import SwiftUI

/// The TokenBar visual identity: the café tab palette (DRD 8.1, D44).
/// The menu bar item stays a monochrome template (DRD 8.3).
enum Theme {
    /// Crema amber. The one brand accent: selection, toggles and buttons. Light: 4.8:1 for white text on it.
    /// Dark: lighter, so tinted button text is 4:1 on a dark button. White text on it is 3:1, as with system blue.
    static let accent = dynamic(light: (0.62, 0.40, 0.12), dark: (0.76, 0.53, 0.22))

    /// Bar fill below 80%: espresso in light mode, latte cream in dark mode.
    static let coffee = dynamic(light: (0.42, 0.27, 0.17), dark: (0.80, 0.70, 0.60))
    /// Bar fill 80–99%: bright orange. It is far from `coffee` in both modes (a test checks the distance).
    static let warning = dynamic(light: (0.86, 0.40, 0.02), dark: (1.00, 0.58, 0.12))
    /// Bar fill 100%: red.
    static let danger = dynamic(light: (0.75, 0.10, 0.12), dark: (1.00, 0.30, 0.30))

    /// Warm paper: light cream in light mode, deep espresso in dark mode.
    static let paper = dynamic(light: (0.97, 0.94, 0.90), dark: (0.13, 0.09, 0.06))
    /// Text on paper. The contrast is 15:1 in both modes.
    static let ink = dynamic(light: (0.13, 0.08, 0.06), dark: (0.97, 0.94, 0.90))
    /// Secondary and tertiary text. The system `.secondary` is ink at 50% here, 3.8:1 on light paper, below WCAG AA.
    /// These levels are 4.9:1 or more on paper and on the latte headline in both modes.
    static let secondary = ink.opacity(0.75)
    static let tertiary = ink.opacity(0.65)
    /// Hairlines and the quiet surface of the index headline.
    static let latte = dynamic(light: (0.89, 0.84, 0.75), dark: (0.26, 0.18, 0.13))
    /// Fixed cream and ink for the share card, which is always light (DRD 7.7).
    static let cream = Color(red: 0.97, green: 0.94, blue: 0.90)
    static let espresso = Color(red: 0.13, green: 0.08, blue: 0.06)

    /// A one-point latte rule between popover sections. It replaces `Divider`.
    static var hairline: some View { Rectangle().fill(latte).frame(height: 1) }

    /// A dashed receipt rule, for the share card.
    static var dashed: some View {
        GeometryReader { proxy in
            Path { $0.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                $0.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2)) }
                .stroke(espresso.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 1)
    }

    /// The value pairs are sRGB. A test reads both values through `NSAppearance`.
    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        func ns(_ c: (Double, Double, Double)) -> NSColor { NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1) }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }
}

extension View {
    /// Ink on paper, with the accent tint. The paper fills the full window, so no material edge shows.
    func onPaper() -> some View {
        foregroundStyle(Theme.ink)
            .background(Theme.paper)
            .tint(Theme.accent)
    }
}
