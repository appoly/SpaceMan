/// One ring segment, with its angles as fractions of the circle measured clockwise from the top.
nonisolated struct SunburstSegment: Identifiable, Sendable {
    enum Content: Sendable {
        case item(StorageItem)
        case unlisted(Int64)
        case freeSpace(Int64)
    }

    let content: Content
    let parentID: StorageItem.ID?
    let depth: Int
    let start: Double
    let end: Double

    var id: String {
        switch content {
        case let .item(item): item.id
        case .unlisted: "chart:unlisted"
        case .freeSpace: "chart:free"
        }
    }

    var midpoint: Double {
        (start + end) / 2
    }
}

nonisolated extension SunburstSegment.Content {
    var title: String {
        switch self {
        case let .item(item): item.title
        case .unlisted: "Unlisted space"
        case .freeSpace: "Free space"
        }
    }

    var size: Int64 {
        switch self {
        case let .item(item): item.size
        case let .unlisted(size), let .freeSpace(size): size
        }
    }

    var item: StorageItem? {
        switch self {
        case let .item(item): item
        case .unlisted, .freeSpace: nil
        }
    }
}

/// Lays items out as concentric rings, each child within its parent's arc. Arcs too thin to see are dropped along
/// with their descendants.
nonisolated struct SunburstLayout: Sendable {
    let segments: [SunburstSegment]
    /// Where the items end and free or unlisted space begins, so colours spread across the items alone.
    let itemsEnd: Double
    let unlisted: Int64
    let freeSpace: Int64

    var depth: Int {
        segments.map(\.depth).max() ?? 0
    }

    /// Space in `total` that's neither free nor one of `items` shows as unlisted.
    init(items: [StorageItem], total: Int64, freeSpace: Int64 = 0, maxDepth: Int, minimumFraction: Double) {
        let itemsTotal = items.reduce(0) { $0 + $1.size }
        let freeSpace = max(0, freeSpace)
        let unlisted = max(0, total - freeSpace - itemsTotal)
        let circle = itemsTotal + unlisted + freeSpace
        self.unlisted = unlisted
        self.freeSpace = freeSpace
        guard circle > 0 else {
            segments = []
            itemsEnd = 0
            return
        }

        var builder = Builder(maxDepth: maxDepth, minimumFraction: minimumFraction)
        builder.lay(items, parentID: nil, from: 0, scale: 1 / Double(circle), depth: 1)
        var segments = builder.segments
        itemsEnd = Double(itemsTotal) / Double(circle)
        var position = itemsEnd
        for content in [SunburstSegment.Content.unlisted(unlisted), .freeSpace(freeSpace)] {
            let span = Double(content.size) / Double(circle)
            if span >= minimumFraction {
                segments.append(SunburstSegment(
                    content: content, parentID: nil, depth: 1, start: position, end: position + span
                ))
            }
            position += span
        }
        self.segments = segments
    }

    func segment(atFraction fraction: Double, depth: Int) -> SunburstSegment? {
        segments.first { $0.depth == depth && $0.start <= fraction && fraction < $0.end }
    }

    /// The IDs from the outermost ring's parent down to `segment` itself.
    func lineage(of segment: SunburstSegment) -> [StorageItem.ID] {
        var lineage = [segment.id]
        var parentID = segment.parentID
        while let id = parentID {
            lineage.insert(id, at: 0)
            parentID = segments.first { $0.id == id }?.parentID
        }
        return lineage
    }
}

nonisolated private struct Builder {
    let maxDepth: Int
    let minimumFraction: Double
    var segments: [SunburstSegment] = []

    mutating func lay(
        _ items: [StorageItem], parentID: StorageItem.ID?, from start: Double, scale: Double, depth: Int
    ) {
        var position = start
        for item in items.sortedBySize {
            let span = Double(item.size) * scale
            defer { position += span }
            guard span >= minimumFraction else { continue }
            segments.append(SunburstSegment(
                content: .item(item), parentID: parentID, depth: depth, start: position, end: position + span
            ))
            guard let children = item.children, depth < maxDepth else { continue }
            let childrenTotal = max(item.size, children.reduce(0) { $0 + $1.size })
            guard childrenTotal > 0 else { continue }
            lay(children, parentID: item.id, from: position, scale: span / Double(childrenTotal), depth: depth + 1)
        }
    }
}
