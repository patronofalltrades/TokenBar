import AppKit
import SwiftUI

/// The `MenuBarExtra` label (DRD 2.2 and 2.4): one template symbol and one value, no color.
/// The width is fixed, so a new value does not move the other menu bar items (TRD 8).
struct MenuBarLabel: View {
    nonisolated static let width: CGFloat = 52
    nonisolated static let spacing: CGFloat = 3

    let snapshot: DisplaySnapshot

    var body: some View {
        Image(nsImage: Self.image(symbol: snapshot.menuBarSymbol, text: snapshot.menuBarText))
            .accessibilityLabel(Self.voiceOverLabel(snapshot, now: .now))
    }

    /// `MenuBarExtra` ignores SwiftUI frames: the item width follows the text. A fixed-width template image keeps 52 pt.
    nonisolated static func image(symbol: String, text: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular)) ?? NSImage()
        let value = NSAttributedString(string: text, attributes: [.font: font])
        let height = max(icon.size.height, value.size().height)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            icon.draw(in: NSRect(origin: NSPoint(x: 0, y: (height - icon.size.height) / 2), size: icon.size))
            value.draw(at: NSPoint(x: icon.size.width + spacing, y: (height - value.size().height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// DRD 9.1, for example "TokenBar. Claude Code, 62 percent of 5-hour limit. Today, 3.4 cafés con leche."
    nonisolated static func voiceOverLabel(_ s: DisplaySnapshot, now: Date) -> String {
        let top = DisplayBuilder.topLimit(in: s.rows)
        let name = top.map { DisplayBuilder.name($0.provider) } ?? ""
        let today = s.indexLine.map {
            $0.replacingOccurrences(of: " =", with: ",").replacingOccurrences(of: " ≈", with: ", about") + "."
        }
            ?? "Today, about \(s.costTodayEUR.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))) euros."
        let limit = top.map { "\(name), \(Int($0.limit.usedPercent)) percent of \($0.limit.name) limit." } ?? ""
        let parts: [String] = switch s.state {
        case .noData: ["No usage data. Click to set up."]
        case .error: ["Cannot read the usage data."]
        case .warning: ["Warning.", limit, today]
        case .normal: [limit, today]
        case .limitHit:
            ["\(name) limit reached."] + (top?.limit.resetsAt.map { reset in
                let f = DateComponentsFormatter()
                f.unitsStyle = .full
                f.allowedUnits = [.day, .hour, .minute]
                f.maximumUnitCount = 2
                return ["Resets in \(f.string(from: max(60, reset.timeIntervalSince(now))) ?? "")."]
            } ?? [])
        }
        return (["TokenBar."] + parts.filter { !$0.isEmpty }).joined(separator: " ")
    }
}
