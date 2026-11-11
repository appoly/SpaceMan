import AppKit
import SwiftUI

struct SunburstChart: View {
    let layout: SunburstLayout
    let title: String
    let size: Int64
    let selectedID: StorageItem.ID?
    let highlightedID: SunburstSegment.ID?
    @Binding var hovered: SunburstSegment?
    let activate: (SunburstSegment) -> Void
    /// `nil` at the top level.
    let goUp: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let rings = RingGeometry(size: proxy.size, depth: layout.depth)
            Canvas { context, _ in
                let separator = Color(nsColor: .windowBackgroundColor)
                for segment in layout.segments {
                    let path = rings.path(for: segment)
                    context.fill(path, with: .color(segment.colour(hueSpan: layout.itemsEnd)))
                    if segment.id == highlightedID {
                        context.fill(path, with: .color(.white.opacity(0.3)))
                    }
                    context.stroke(path, with: .color(separator), lineWidth: 1)
                }
                if let selected = layout.segments.first(where: { $0.id == selectedID }) {
                    context.stroke(rings.path(for: selected), with: .color(.primary), lineWidth: 2)
                }
            }
            .overlay {
                CentreLabel(
                    title: hovered?.content.title ?? title,
                    size: hovered?.content.size ?? size,
                    showsUpArrow: goUp != nil && hovered == nil
                )
                .frame(width: rings.holeRadius * 1.6)
                .position(rings.centre)
                .allowsHitTesting(false)
            }
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    let segment = rings.segment(at: location, in: layout)
                    if segment?.id != hovered?.id {
                        hovered = segment
                    }
                case .ended:
                    hovered = nil
                }
            }
            .onTapGesture { location in
                if rings.isInHole(location) {
                    goUp?()
                } else if let segment = rings.segment(at: location, in: layout) {
                    activate(segment)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Chart of \(title)")
    }
}

private struct CentreLabel: View {
    let title: String
    let size: Int64
    let showsUpArrow: Bool

    var body: some View {
        VStack(spacing: 2) {
            if showsUpArrow {
                Image(systemName: "chevron.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.middle)
            Text(size.formatted(.byteCount(style: .file)))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.6)
    }
}

/// Converts between segments and points in the view, with fractions of the circle running clockwise from the top.
private struct RingGeometry {
    let centre: CGPoint
    let holeRadius: CGFloat
    let ringWidth: CGFloat

    init(size: CGSize, depth: Int) {
        centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(0, min(size.width, size.height) / 2)
        holeRadius = radius * 0.3
        ringWidth = depth > 0 ? (radius - holeRadius) / CGFloat(depth) : 0
    }

    func path(for segment: SunburstSegment) -> Path {
        let inner = holeRadius + ringWidth * CGFloat(segment.depth - 1)
        let start = Angle.radians(segment.start * 2 * .pi - .pi / 2)
        let delta = Angle.radians((segment.end - segment.start) * 2 * .pi)
        var path = Path()
        path.addRelativeArc(center: centre, radius: inner + ringWidth, startAngle: start, delta: delta)
        path.addRelativeArc(center: centre, radius: inner, startAngle: start + delta, delta: .radians(-delta.radians))
        path.closeSubpath()
        return path
    }

    func isInHole(_ point: CGPoint) -> Bool {
        distance(to: point) < holeRadius
    }

    func segment(at point: CGPoint, in layout: SunburstLayout) -> SunburstSegment? {
        let distance = distance(to: point)
        guard ringWidth > 0, distance >= holeRadius else { return nil }
        let depth = Int((distance - holeRadius) / ringWidth) + 1
        var fraction = (atan2(point.y - centre.y, point.x - centre.x) + .pi / 2) / (2 * .pi)
        if fraction < 0 {
            fraction += 1
        }
        return layout.segment(atFraction: Double(fraction), depth: depth)
    }

    private func distance(to point: CGPoint) -> CGFloat {
        hypot(point.x - centre.x, point.y - centre.y)
    }
}

extension SunburstSegment {
    /// Hue follows the segment's position around the circle, so children stay close to their parent's colour.
    func colour(hueSpan: Double) -> Color {
        switch content {
        case let .item(item):
            switch item.kind {
            case .remainder:
                return .gray.opacity(0.5)
            case .category, .group, .entry:
                let hue = hueSpan > 0 ? midpoint / hueSpan * 0.85 : 0
                let ring = Double(depth - 1)
                return Color(hue: hue, saturation: max(0.25, 0.65 - ring * 0.1), brightness: min(1, 0.85 + ring * 0.04))
            }
        case .unlisted:
            return .gray.opacity(0.3)
        case .freeSpace:
            return .secondary.opacity(0.12)
        }
    }
}
