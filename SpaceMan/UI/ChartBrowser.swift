import SwiftUI

/// The scan as a drillable sunburst, with a trail of the folders opened and a legend for the focused or hovered item.
struct ChartBrowser: View {
    private static let maxDepth = 5
    private static let minimumFraction = 1.0 / 720
    private static let volumeName = (try? URL(filePath: "/").resourceValues(forKeys: [.volumeNameKey]))?
        .volumeName ?? "Disk"

    let items: [StorageItem]
    let capacity: DiskCapacity?
    @Binding var focusPath: [StorageItem.ID]
    @Binding var selection: StorageItem.ID?
    @State private var hovered: SunburstSegment?
    @State private var legendHighlightID: SunburstSegment.ID?
    @State private var isWide = true

    var body: some View {
        let trail = trail
        let layout = layout(focus: trail.last)
        VStack(alignment: .leading, spacing: 0) {
            Breadcrumbs(rootTitle: Self.volumeName, trail: trail, navigate: navigate(toDepth:))
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            let stack = isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            stack {
                SunburstChart(
                    layout: layout,
                    title: trail.last?.title ?? Self.volumeName,
                    size: focusSize(trail.last),
                    selectedID: selection,
                    highlightedID: hovered?.id ?? legendHighlightID,
                    hovered: $hovered,
                    activate: { activate($0, in: layout) },
                    goUp: trail.isEmpty ? nil : { navigate(toDepth: trail.count - 1) }
                )
                .id(trail.last?.id)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                legend(trail: trail, layout: layout)
                    .frame(width: isWide ? 280 : nil, height: isWide ? nil : 200)
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 640 } action: { isWide = $0 }
    }

    /// The opened items, stopping at the first ID a rescan or clean-up has removed.
    private var trail: [StorageItem] {
        var level = items
        var trail: [StorageItem] = []
        for id in focusPath {
            guard let item = level.first(where: { $0.id == id }), let children = item.children else { break }
            trail.append(item)
            level = children
        }
        return trail
    }

    private func layout(focus: StorageItem?) -> SunburstLayout {
        if let focus {
            return SunburstLayout(
                items: focus.children ?? [], total: focus.size, maxDepth: Self.maxDepth,
                minimumFraction: Self.minimumFraction
            )
        }
        return SunburstLayout(
            items: items, total: capacity?.total ?? 0, freeSpace: capacity?.available ?? 0, maxDepth: Self.maxDepth,
            minimumFraction: Self.minimumFraction
        )
    }

    private func focusSize(_ focus: StorageItem?) -> Int64 {
        focus?.size ?? capacity?.used ?? items.reduce(0) { $0 + $1.size }
    }

    @ViewBuilder
    private func legend(trail: [StorageItem], layout: SunburstLayout) -> some View {
        if let hovered {
            ChartLegend(
                title: hovered.content.title,
                size: hovered.content.size,
                rows: rows(for: hovered.content.item?.children ?? [], in: layout),
                highlightedID: $legendHighlightID,
                open: nil
            )
        } else {
            let focus = trail.last
            ChartLegend(
                title: focus?.title ?? Self.volumeName,
                size: focusSize(focus),
                rows: rows(for: focus?.children ?? items, in: layout) + extraRows(in: layout),
                highlightedID: $legendHighlightID,
                open: { open($0, under: trail) }
            )
        }
    }

    private func rows(for items: [StorageItem], in layout: SunburstLayout) -> [ChartLegend.Row] {
        items.sortedBySize.map { item in
            let segment = layout.segments.first { $0.id == item.id }
            return ChartLegend.Row(
                id: item.id,
                title: item.title,
                size: item.size,
                colour: segment?.colour(hueSpan: layout.itemsEnd) ?? .gray.opacity(0.3),
                item: item
            )
        }
    }

    private func extraRows(in layout: SunburstLayout) -> [ChartLegend.Row] {
        layout.segments.compactMap { segment in
            switch segment.content {
            case .item:
                nil
            case .unlisted, .freeSpace:
                ChartLegend.Row(
                    id: segment.id, title: segment.content.title, size: segment.content.size,
                    colour: segment.colour(hueSpan: layout.itemsEnd), item: nil
                )
            }
        }
    }

    private func activate(_ segment: SunburstSegment, in layout: SunburstLayout) {
        guard let item = segment.content.item else { return }
        selection = item.id
        guard item.children != nil else { return }
        hovered = nil
        withAnimation {
            focusPath = trail.map(\.id) + layout.lineage(of: segment)
        }
    }

    private func open(_ item: StorageItem, under trail: [StorageItem]) {
        selection = item.id
        guard item.children != nil else { return }
        legendHighlightID = nil
        withAnimation {
            focusPath = trail.map(\.id) + [item.id]
        }
    }

    private func navigate(toDepth depth: Int) {
        let kept = trail.prefix(depth)
        if let last = kept.last {
            selection = last.id
        }
        hovered = nil
        withAnimation {
            focusPath = kept.map(\.id)
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
        .defaultScrollAnchor(.trailing)
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

private struct ChartLegend: View {
    struct Row: Identifiable {
        let id: SunburstSegment.ID
        let title: String
        let size: Int64
        let colour: Color
        let item: StorageItem?
    }

    let title: String
    let size: Int64
    let rows: [Row]
    @Binding var highlightedID: SunburstSegment.ID?
    /// `nil` while the legend describes a hovered segment, whose rows the pointer can't reach.
    let open: ((StorageItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.bold())
                    .lineLimit(2)
                Spacer()
                Text(size.formatted(.byteCount(style: .file)))
                    .font(.title3)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        if let item = row.item, let open {
                            Button { open(item) } label: { label(for: row) }
                                .buttonStyle(.plain)
                        } else {
                            label(for: row)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func label(for row: Row) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(row.colour)
                .frame(width: 8, height: 8)
            Text(row.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(row.isMuted ? .secondary : .primary)
            Spacer()
            Text(row.size.formatted(.byteCount(style: .file)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.selection.opacity(row.id == highlightedID ? 0.4 : 0), in: .rect(cornerRadius: 4))
        .contentShape(.rect)
        .onHover { isHovering in
            if isHovering {
                highlightedID = row.id
            } else if highlightedID == row.id {
                highlightedID = nil
            }
        }
    }
}

private extension ChartLegend.Row {
    var isMuted: Bool {
        switch item?.kind {
        case .remainder, nil: true
        case .category, .group, .entry: false
        }
    }
}
