import AppKit
import SwiftUI

/// The share card (DRD 7.7, TRD-T27). The card uses only the snapshot lines that the popover
/// already shows. The snapshot has no user name, file paths, project names or prompt content.
/// A model name gets onto the card only through a roast that uses `{model}`.
enum ShareCard {
    struct Line: Equatable {
        var text: String
        var symbol: String? = nil   // SF Symbol for the image
        var emoji: String? = nil    // prefix for the clipboard text
        var isRoast = false
    }

    /// "TokenBar · github.com/patronofalltrades/TokenBar".
    static let footer = "TokenBar · " + (Links.repository.host() ?? "") + Links.repository.path()

    /// The card lines, without the footer: the selected index only (D41).
    /// No index yet gives the numbers card (DRD 7.7 rule 7), the same as in `DisplayBuilder`.
    static func lines(_ s: DisplaySnapshot, locale: Locale = .current) -> [Line] {
        guard s.index != nil else {
            return [Line(text: "Today \(PopoverFormat.euro(s.costTodayEUR, locale: locale))", symbol: "eurosign.circle"),
                    Line(text: "Week \(PopoverFormat.euro(s.costWeekEUR, locale: locale)) (API-equivalent)", symbol: "calendar")]
        }
        var lines: [Line] = []
        if let line = s.indexLine { lines.append(Line(text: line, symbol: s.indexSymbol, emoji: s.indexEmoji)) }
        if let detail = s.indexDetail { lines.append(Line(text: detail, symbol: "calendar")) }
        if let roast = s.roast { lines.append(Line(text: "“\(roast)”", isRoast: true)) }
        return lines
    }

    /// The clipboard text. A blank line separates the roast and the footer.
    static func text(_ s: DisplaySnapshot, locale: Locale = .current) -> String {
        let body = lines(s, locale: locale).map { line in
            (line.isRoast ? "\n" : "") + (line.emoji.map { $0 + " " } ?? "") + line.text
        }
        return (body + ["", footer]).joined(separator: "\n")
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

/// 360 pt wide. Light appearance and an opaque background, so the card looks the same in every chat app.
struct ShareCardView: View {
    let lines: [ShareCard.Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if line.isRoast {
                    Text(line.text).font(.callout).italic().foregroundStyle(.secondary).padding(.top, 6)
                } else {
                    Label(line.text, systemImage: line.symbol ?? "cup.and.saucer.fill")
                        .font(index == 0 ? .title3.weight(.semibold) : .callout)
                        .monospacedDigit()
                }
            }
            Text(ShareCard.footer).font(.caption).foregroundStyle(.tertiary).padding(.top, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .symbolRenderingMode(.hierarchical)
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

#Preview("Café") { ShareCardView(lines: ShareCard.lines(PopoverSamples.normal)) }
#Preview("Water") { ShareCardView(lines: ShareCard.lines(PopoverSamples.water)) }
#Preview("Tuition") { ShareCardView(lines: ShareCard.lines(PopoverSamples.tuition)) }
