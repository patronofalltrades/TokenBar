import AppKit
import SwiftUI

/// The TokenBar visual identity: two colors in each mode (DRD 8.1, D45).
/// Light mode is IESE red on white. Dark mode is white on IESE near-black. The modes never mix red and black.
/// The values come from the iese.edu style sheet. The menu bar item stays a monochrome template (DRD 8.3).
enum Theme {
    /// IESE red. #E00000, not #FF0000: white on it is 5:1, red on white is 5:1 (WCAG AA). Pure red gives 4:1.
    private static let red = (0.878, 0.0, 0.0)
    private static let white = (1.0, 1.0, 1.0)
    private static let black = (0.118, 0.118, 0.118)  // IESE #1E1E1E

    /// The window background.
    static let paper = dynamic(light: white, dark: black)
    /// All text, and the selection outline. Light: red, 5:1 on white. Dark: near-white, 15:1.
    static let ink = dynamic(light: red, dark: (0.96, 0.96, 0.96))
    /// The strong surface: the index headline and the main button, with `paper` text on it.
    static let accent = dynamic(light: red, dark: white)
    /// Secondary and tertiary text. Light: solid red, because red with opacity is below 4.5:1 on white.
    /// Dark: grays, 7:1 or more on near-black.
    static let secondary = dynamic(light: red, dark: (0.78, 0.78, 0.78))
    static let tertiary = dynamic(light: red, dark: (0.70, 0.70, 0.70))
    /// The tint of system controls (toggles and pickers). Dark: gray, because a white tint hides the white knob.
    static let control = dynamic(light: red, dark: (0.55, 0.55, 0.55))

    /// Hairlines and quiet outlines: a tint of the ink.
    static let rule = dynamic(light: (0.97, 0.78, 0.78), dark: (0.30, 0.30, 0.30))
    /// Bar track and small chips.
    static let track = dynamic(light: (0.99, 0.91, 0.91), dark: (0.24, 0.24, 0.24))
    /// Bar fill below 80%: a half tint of the ink.
    static let bar = dynamic(light: (0.94, 0.55, 0.55), dark: (0.58, 0.58, 0.58))
    /// Bar fill from 80%: the full ink. The text and the icon tell 80% from 100% (DRD 9.3).
    static let high = ink

    /// Fixed red on white for the share card, which is always light (DRD 7.7).
    static let cardPaper = Color.white
    static let cardInk = Color(red: red.0, green: red.1, blue: red.2)

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
            .tint(Theme.control)
    }
}

/// The main action: `paper` text on an `accent` surface. Not filled: an `accent` outline (DRD 8.1).
struct ThemeButtonStyle: ButtonStyle {
    var filled = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(filled ? .semibold : .regular))
            .padding(.horizontal, 14).padding(.vertical, 5)
            .foregroundStyle(filled ? Theme.paper : Theme.ink)
            .background(filled ? Theme.accent : Theme.paper, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: filled ? 0 : 1))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
    }
}
