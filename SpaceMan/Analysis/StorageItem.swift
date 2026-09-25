nonisolated struct StorageItem: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case category
        case group
        case entry
        case remainder
    }

    let id: String
    var kind: Kind = .entry
    let title: String
    var subtitle: String?
    var path: String?
    var size: Int64
    let category: StorageCategory
    var about: String?
    var flags: [String] = []
    var isFile = false
    var unreadablePaths: [String] = []
    /// `nil` for leaves, as `Table`/`OutlineGroup` require.
    var children: [StorageItem]?

    var flagCount: Int {
        flags.count + (children ?? []).reduce(0) { $0 + $1.flagCount }
    }
}

extension [StorageItem] {
    nonisolated var sortedBySize: [StorageItem] {
        sorted { $0.size > $1.size }
    }

    nonisolated func item(withID id: StorageItem.ID) -> StorageItem? {
        for item in self {
            if item.id == id {
                return item
            }
            if let match = item.children?.item(withID: id) {
                return match
            }
        }
        return nil
    }
}
