nonisolated struct StorageItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var subtitle: String?
    var path: String?
    var size: Int64
    let category: StorageCategory
    var about: String?
    var flags: [String] = []
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
}
