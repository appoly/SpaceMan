import Observation
import SwiftUI

/// Kept by the window so the inspector can describe what the chart is pointing at.
@Observable
final class ChartState {
    var focusPath: [StorageItem.ID] = []
    var hovered: SunburstSegment?
    /// The inspector row under the pointer, whose segment the chart highlights.
    var highlightedRowID: String?
}

/// The chart's layout for one level, worked out once per update and shared with the inspector.
struct ChartScene {
    private static let maxDepth = 5
    private static let minimumFraction = 1.0 / 720
    private static let volumeName = (try? URL(filePath: "/").resourceValues(forKeys: [.volumeNameKey]))?
        .volumeName ?? "Disk"

    let items: [StorageItem]
    let capacity: DiskCapacity?
    let palette: SunburstPalette
    /// The opened items, stopping at the first ID a rescan or clean-up has removed.
    let trail: [StorageItem]
    let layout: SunburstLayout

    init(items: [StorageItem], capacity: DiskCapacity?, palette: SunburstPalette, focusPath: [StorageItem.ID]) {
        self.items = items
        self.capacity = capacity

        var level = items
        var trail: [StorageItem] = []
        for id in focusPath {
            guard let item = level.first(where: { $0.id == id }), let children = item.children else { break }
            trail.append(item)
            level = children
        }
        self.trail = trail
        // Below the top level everything shares one category, so its shades can't tell segments apart.
        self.palette = trail.isEmpty ? palette : .position

        layout = if let focus = trail.last {
            SunburstLayout(
                items: focus.children ?? [], total: focus.size, maxDepth: Self.maxDepth,
                minimumFraction: Self.minimumFraction
            )
        } else {
            SunburstLayout(
                items: items, total: capacity?.total ?? 0, freeSpace: capacity?.available ?? 0,
                maxDepth: Self.maxDepth, minimumFraction: Self.minimumFraction
            )
        }
    }

    var rootTitle: String {
        Self.volumeName
    }

    var rootSize: Int64 {
        capacity?.used ?? items.reduce(0) { $0 + $1.size }
    }

    var title: String {
        trail.last?.title ?? rootTitle
    }

    var size: Int64 {
        trail.last?.size ?? rootSize
    }

    /// Children too small to draw get a neutral dot.
    func rows(for items: [StorageItem]) -> [ContentsRow] {
        items.sortedBySize.map { item in
            ContentsRow(
                item: item,
                colour: layout.segments.first { $0.id == item.id }.map(colour(of:)) ?? .gray.opacity(0.3)
            )
        }
    }

    /// Free and unlisted space, shown only at the top level.
    var extraRows: [ContentsRow] {
        layout.segments.compactMap { segment in
            switch segment.content {
            case .item:
                nil
            case .unlisted, .freeSpace:
                ContentsRow(
                    id: segment.id, title: segment.content.title, size: segment.content.size,
                    colour: colour(of: segment), item: nil
                )
            }
        }
    }

    func colour(of segment: SunburstSegment) -> Color {
        segment.colour(palette: palette, hueSpan: layout.itemsEnd)
    }
}

/// The scan as a drillable sunburst, with a trail of the items opened above it.
struct ChartBrowser: View {
    let scene: ChartScene
    @Bindable var state: ChartState
    let selection: StorageItem.ID?
    let open: (StorageItem) -> Void
    let navigate: (_ depth: Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Breadcrumbs(rootTitle: scene.rootTitle, trail: scene.trail, navigate: navigate)
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            SunburstChart(
                layout: scene.layout,
                palette: scene.palette,
                title: scene.title,
                size: scene.size,
                selectedID: selection,
                highlightedID: state.hovered?.id ?? state.highlightedRowID,
                hovered: $state.hovered,
                activate: { segment in
                    if let item = segment.content.item {
                        open(item)
                    }
                },
                goUp: scene.trail.isEmpty ? nil : { navigate(scene.trail.count - 1) }
            )
            .id(scene.trail.last?.id)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct Breadcrumbs: View {
    let rootTitle: String
    let trail: [StorageItem]
    let navigate: (_ depth: Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                crumb(rootTitle, depth: 0)
                ForEach(Array(trail.enumerated()), id: \.element.id) { index, item in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    crumb(item.title, depth: index + 1)
                }
            }
            .lineLimit(1)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.leading, for: .alignment)
        .defaultScrollAnchor(.trailing, for: .initialOffset)
        .defaultScrollAnchor(.trailing, for: .sizeChanges)
    }

    @ViewBuilder
    private func crumb(_ title: String, depth: Int) -> some View {
        if depth == trail.count {
            Text(title).fontWeight(.semibold)
        } else {
            Button(title) { navigate(depth) }
                .buttonStyle(.link)
        }
    }
}
