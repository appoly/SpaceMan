/// The scanned tree laid out by folder, annotated with what the catalogue identified each folder as.
nonisolated enum LocationTree {
    static let idPrefix = "location:"

    static func items(root: FSNode, categories: [StorageItem], minimumSize: Int64) -> [StorageItem] {
        var identified: [String: StorageItem] = [:]
        collectIdentified(categories, into: &identified)
        return children(of: root, at: "/", identified: identified, minimumSize: minimumSize) ?? []
    }

    private static func collectIdentified(_ items: [StorageItem], into identified: inout [String: StorageItem]) {
        for item in items {
            if item.kind == .entry, item.category != .other, let path = item.path {
                identified[path] = item
            }
            collectIdentified(item.children ?? [], into: &identified)
        }
    }

    /// A catch-all match covers only what deeper rules left, so its name ("Other Xcode data") doesn't describe the
    /// whole folder.
    private static func identifiedName(of match: StorageItem, forFolder folder: FSNode) -> String? {
        guard match.size == folder.size, match.title != folder.name else { return nil }
        return match.title
    }

    private static func children(
        of node: FSNode, at path: String, identified: [String: StorageItem], minimumSize: Int64
    ) -> [StorageItem]? {
        guard !node.children.isEmpty else { return nil }
        var items = node.children.filter { $0.size >= minimumSize }.map { child in
            let childPath = path.appendingPathComponent(child.name)
            let match = identified[childPath]
            return StorageItem(
                id: idPrefix + childPath,
                title: child.name,
                path: childPath,
                size: child.size,
                category: match?.category ?? .other,
                about: match?.about,
                flags: match?.flags ?? [],
                isFile: !child.isDirectory,
                identifiedAs: match.flatMap { identifiedName(of: $0, forFolder: child) },
                children: children(of: child, at: childPath, identified: identified, minimumSize: minimumSize)
            )
        }
        let remainder = node.size - items.reduce(0) { $0 + $1.size }
        if remainder >= minimumSize {
            items.append(StorageItem(
                id: idPrefix + path + "#remainder", kind: .remainder, title: "Smaller items", path: path,
                size: remainder, category: .other
            ))
        }
        return items.sortedBySize
    }
}
