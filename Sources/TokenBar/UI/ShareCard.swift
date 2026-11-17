import AppKit
import Charts
import SwiftUI

/// The share card (DRD 7.7, TRD-T27). The card uses only the snapshot lines that the popover
/// already shows. The snapshot has no user name, file paths, project names or prompt content.
/// A model name gets onto the card only through a roast that uses `{model}`.
enum ShareCard {
    struct Line: Equatable {
        var text: String
        var symbol: String? = nil   // icon name for the image (`Icon`)
        var emoji: String? = nil    // prefix for the clipboard text
        var isRoast = false
        var trend: [Double] = []    // the values of the sparkline below the line. Empty: no sparkline.
    }

    /// "TokenBar · github.com/patronofalltrades/TokenBar".
    static let footer = "TokenBar · " + (Links.repository.host() ?? "") + Links.repository.path()

    /// The card lines, without the footer: the selected index only (D41). EUR only in the calculation line (D47).
    /// No index yet gives no lines. The popover then has no Share button (DRD 7.7 rule 7).
    static func lines(_ s: DisplaySnapshot) -> [Line] {
        guard s.index != nil else { return [] }
        var lines: [Line] = []
        if let line = s.indexLine { lines.append(Line(text: line, symbol: s.indexSymbol, emoji: s.indexEmoji)) }
        if let detail = s.indexDetail { lines.append(Line(text: detail, symbol: "calendar")) }
        if let math = s.indexMath { lines.append(Line(text: math, symbol: "function")) }
        // The last 7 days (DRD 7.7 rule 9). A week without usage has no line.
        let trend = s.trend.suffix(7).map(\.value)
        if trend.contains(where: { $0 > 0 }) {
            lines.append(Line(text: "Last 7 days", symbol: "chart.line.uptrend.xyaxis", emoji: "📈", trend: trend))
        }
        if let roast = s.roast { lines.append(Line(text: "“\(roast)”", isRoast: true)) }
        return lines
    }

    /// The clipboard text. A blank line separates the roast and the footer.
    static func text(_ s: DisplaySnapshot) -> String {
        let body = lines(s).map { line in
            (line.isRoast ? "\n" : "") + (line.emoji.map { $0 + " " } ?? "") + line.text
                + (line.trend.isEmpty ? "" : " " + bars(line.trend))
        }
        return (body + ["", footer]).joined(separator: "\n")
    }

    /// The sparkline of the clipboard text: one block character for each value, for example "▃▅▁▇▄█▆".
    /// The largest value is the full block.
    static func bars(_ values: [Double]) -> String {
        let blocks = Array("▁▂▃▄▅▆▇█")
        let top = values.max() ?? 0
        return String(values.map { blocks[top > 0 ? Int((max(0, $0) / top * 7).rounded()) : 0] })
    }

    @MainActor static func image(_ s: DisplaySnapshot) -> CGImage? {
        let renderer = ImageRenderer(content: ShareCardView(lines: lines(s)))
        renderer.scale = 2
        return renderer.cgImage
    }

    /// Writes the PNG image and the text in one pasteboard item. No network request.
    @MainActor static func copy(_ s: DisplaySnapshot, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let image = image(s),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString(text(s), forType: .string)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

/// A receipt, 360 pt wide: IESE red on white paper, with dashed rules (D45). Light appearance and an opaque background,
/// so the card looks the same in every chat app.
struct ShareCardView: View {
    let lines: [ShareCard.Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if line.isRoast {
                    Text(line.text).font(.callout).italic().foregroundStyle(Theme.cardInk.opacity(0.75)).padding(.vertical, 4)
                } else {
                    Icon.label(line.text, icon: line.symbol ?? IndexChoice.cafe.rawValue, style: index == 0 ? .title3 : .callout)
                        .font(index == 0 ? .title3.weight(.semibold) : .callout)
                        .monospacedDigit()
                }
                if !line.trend.isEmpty {
                    // ponytail: the popover has a second copy of this chart, with the pointer. Share one view at the third use.
                    Chart(Array(line.trend.enumerated()), id: \.offset) { day, value in
                        LineMark(x: .value("Day", day), y: .value("Value", value))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(Theme.cardInk)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 36)
                }
                Theme.dashed
            }
            Text(ShareCard.footer).font(.caption.monospaced()).foregroundStyle(Theme.cardInk.opacity(0.65))
        }
        .fixedSize(horizontal: false, vertical: true)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(Theme.cardInk)
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(Theme.cardPaper)
        .environment(\.colorScheme, .light)
    }
}

#Preview("Café") { ShareCardView(lines: ShareCard.lines(PopoverSamples.normal)) }
#Preview("Water") { ShareCardView(lines: ShareCard.lines(PopoverSamples.water)) }
#Preview("Tuition") { ShareCardView(lines: ShareCard.lines(PopoverSamples.tuition)) }
