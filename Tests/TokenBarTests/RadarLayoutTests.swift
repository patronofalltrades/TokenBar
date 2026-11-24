import Foundation
import Testing
@testable import TokenBar

/// D61: with 4 and 5 axes the labels lay across the ring and the filled shape.
/// The chart is 268 pt wide: the 288 pt popover body minus the 10 pt padding of a card on each side.
@Test(arguments: 3...6)
func radarLabelsAreOutsideTheRingAndInsideTheChart(count: Int) {
    let size = CGSize(width: 268, height: 130)
    let center = RadarLayout.center(in: size)
    let bounds = CGRect(origin: .zero, size: size)
    var frames: [CGRect] = []
    for index in 0..<count {
        let frame = RadarLayout.label(index, count: count, in: size).frame
        #expect(bounds.contains(frame), "label \(index) of \(count) leaves the chart: \(frame)")
        // The point of the label that is nearest to the center must be farther away than the outer ring.
        let nearest = CGPoint(x: min(max(center.x, frame.minX), frame.maxX), y: min(max(center.y, frame.minY), frame.maxY))
        #expect(hypot(nearest.x - center.x, nearest.y - center.y) > RadarLayout.radius, "label \(index) of \(count) touches the ring")
        for other in frames { #expect(!frame.intersects(other), "labels overlap with \(count) axes") }
        frames.append(frame)
    }
}

@Test func radarAxisZeroPointsUpAndTheVertexIsOnTheRing() {
    let size = CGSize(width: 268, height: 130)
    let top = RadarLayout.point(0, count: 5, scale: 1, in: size)
    #expect(abs(top.x - 134) < 0.001 && abs(top.y - (65 - RadarLayout.radius)) < 0.001)
    #expect(RadarLayout.label(0, count: 5, in: size).side == .center)
}
