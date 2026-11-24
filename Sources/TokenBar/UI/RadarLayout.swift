import Foundation

/// The geometry of the provider radar (DRD 3.2, D61). It has no SwiftUI, so a test can check the labels.
/// The radar has one axis for each provider. The first axis points up. A label sits outside the ring,
/// next to its vertex, and its text grows away from the chart. A label never touches the ring or the edge.
enum RadarLayout {
    /// The distance of the outer ring from the center.
    static let radius: CGFloat = 40
    /// The room for a label: 16 characters of `.caption2`, such as "Claude Code 100%", need about 80 pt.
    static let labelWidth: CGFloat = 88
    static let labelHeight: CGFloat = 12
    /// The distance between the outer ring and a label.
    static let gap: CGFloat = 6

    enum Side: Equatable { case leading, center, trailing }

    static func center(in size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    /// The angle of an axis, in radians. Axis 0 points up.
    static func angle(_ index: Int, count: Int) -> Double { 2 * .pi * Double(index) / Double(count) - .pi / 2 }

    /// A point on an axis. `scale` 1 is the outer ring.
    static func point(_ index: Int, count: Int, scale: Double, in size: CGSize) -> CGPoint {
        let c = center(in: size), a = angle(index, count: count)
        return CGPoint(x: c.x + radius * scale * cos(a), y: c.y + radius * scale * sin(a))
    }

    /// The frame of a label and the side that its text is aligned to inside the frame.
    static func label(_ index: Int, count: Int, in size: CGSize) -> (frame: CGRect, side: Side) {
        let c = center(in: size), a = angle(index, count: count)
        let cosine = cos(a), sine = sin(a)
        let anchor = CGPoint(x: c.x + (radius + gap) * cosine, y: c.y + (radius + gap) * sine)
        let side: Side = cosine > 0.3 ? .leading : cosine < -0.3 ? .trailing : .center
        let x = switch side {
        case .leading: anchor.x
        case .trailing: anchor.x - labelWidth
        case .center: anchor.x - labelWidth / 2
        }
        let y = sine > 0.3 ? anchor.y : sine < -0.3 ? anchor.y - labelHeight : anchor.y - labelHeight / 2
        return (CGRect(x: x, y: y, width: labelWidth, height: labelHeight), side)
    }
}
