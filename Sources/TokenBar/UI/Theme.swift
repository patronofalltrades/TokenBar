import AppKit
import SwiftUI

/// The TokenBar visual identity: IESE red on white, with near-black ink (DRD 8.1, D45).
/// The values come from the iese.edu style sheet: red, white and #1E1E1E. The menu bar item stays a monochrome template (DRD 8.3).
enum Theme {
    /// IESE red, for solid surfaces with white text: the index headline and the share card. 5:1 for white text, in both modes.
    /// Pure #FF0000 gives only 4:1, below WCAG AA for small text.
    static let red = Color(red: 0.878, green: 0, blue: 0)
    /// The tint: selection, toggles and buttons. Dark: lighter, so a red outline is clear on a dark window.
    static let accent = dynamic(light: (0.878, 0, 0), dark: (1.00, 0.27, 0.27))

    /// Bar fill below 80%: near-black in light mode, near-white in dark mode. Red stays for the brand and for 100%.
    static let bar = dynamic(light: (0.118, 0.118, 0.118), dark: (0.92, 0.92, 0.92))
    /// Bar fill 80–99%: bright orange. It is far from `bar` and `danger` in both modes (a test checks the distance).
    static let warning = dynamic(light: (0.86, 0.40, 0.02), dark: (1.00, 0.58, 0.12))
    /// Bar fill 100%: dark red. The text also says "limit reached" (DRD 9.3).
    static let danger = dynamic(light: (0.70, 0, 0), dark: (1.00, 0.30, 0.30))

    /// The window: white in light mode, IESE near-black in dark mode.
    static let paper = dynamic(light: (1, 1, 1), dark: (0.118, 0.118, 0.118))
    /// Text on paper. The contrast is 16:1 in both modes.
    static let ink = dynamic(light: (0.118, 0.118, 0.118), dark: (0.96, 0.96, 0.96))
    /// Secondary and tertiary text. The system `.secondary` is ink at 50%, below WCAG AA on paper.
    /// These levels are 4.9:1 or more on paper in both modes.
    static let secondary = ink.opacity(0.75)
    static let tertiary = ink.opacity(0.65)
    /// Hairlines.
    static let rule = dynamic(light: (0.85, 0.85, 0.85), dark: (0.28, 0.28, 0.28))
    /// Fixed white and ink for the share card, which is always light (DRD 7.7).
    static let cardPaper = Color.white
    static let cardInk = Color(red: 0.118, green: 0.118, blue: 0.118)

    /// A one-point rule between popover sections. It replaces `Divider`.
    static var hairline: some View { Rectangle().fill(rule).frame(height: 1) }

    /// A dashed receipt rule, for the share card.
    static var dashed: some View {
        GeometryReader { proxy in
            Path { $0.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                $0.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2)) }
                .stroke(cardInk.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
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
