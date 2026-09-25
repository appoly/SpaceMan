import Darwin

/// An item that doesn't come from the scanned tree, such as another volume's usage.
nonisolated struct ExtraItem: Sendable {
    let group: String?
    let item: StorageItem
}

/// Maps a scanned tree onto the rule catalogue, producing one `StorageItem` per category. Space no rule claims
/// is reported under `.other` as a folder hierarchy.
nonisolated struct Classifier {
    let root: FSNode
    let rules: [Rule]
    let context: NamingContext
    let minimumSize: Int64

    private struct Match {
        let rule: Rule
        let order: Int
        let path: String
        let node: FSNode
        var depth: Int { path.split(separator: "/").count }
    }

    /// Bundles the category and claimed-paths state threaded through child classification, keeping
    /// `namedChildren`/`folderTree` within the parameter-count limit.
    private struct ClassificationContext {
        let category: StorageCategory
        let claimed: Set<String>
    }

    private struct UnclaimedChild {
        let node: FSNode
        let path: String
        let size: Int64
    }

    func classify(extras: [StorageCategory: [ExtraItem]] = [:]) -> [StorageItem] {
        var claimed = Set<String>()
        var placed: [StorageCategory: [(group: String?, item: StorageItem)]] = [:]

        let matches = rules.enumerated()
            .flatMap { order, rule in
                resolve(rule.pattern).map { Match(rule: rule, order: order, path: $0.path, node: $0.node) }
            }
            .sorted { ($0.depth, -$0.order) > ($1.depth, -$1.order) }

        for match in matches where !claimed.contains(match.path) {
            let size = match.node.size - claimedSize(within: match.node, at: match.path, claimed: claimed)
            if size >= minimumSize {
                let entry = (match.rule.group, item(for: match, size: size, claimed: claimed))
                placed[match.rule.category, default: []].append(entry)
            }
            claimed.insert(match.path)
        }

        for (category, items) in extras {
            placed[category, default: []] += items.map { ($0.group, $0.item) }
        }

        let unclaimed = root.size - claimedSize(within: root, at: "/", claimed: claimed)
        if unclaimed >= minimumSize {
            let classification = ClassificationContext(category: .other, claimed: claimed)
            let other = folderTree(
                root, at: "/", total: unclaimed, classification: classification, compressChains: true
            )
            placed[.other, default: []] += (other ?? []).map { (nil, $0) }
        }

        return StorageCategory.allCases.compactMap { category in
            guard let entries = placed[category], !entries.isEmpty else { return nil }
            return categoryItem(category, entries: entries)
        }
        .sortedBySize
    }

    // MARK: - Matching

    private func resolve(_ pattern: String) -> [(path: String, node: FSNode)] {
        let absolute = pattern.hasPrefix("~") ? context.home + pattern.dropFirst() : pattern
        var frontier = [(path: "/", node: root)]
        for component in absolute.split(separator: "/").map(String.init) {
            let isWildcard = component.contains(where: { "*?[".contains($0) })
            frontier = frontier.flatMap { parent in
                parent.node.children
                    .filter { isWildcard ? fnmatch(component, $0.name, 0) == 0 : $0.name == component }
                    .map { (parent.path.appendingPathComponent($0.name), $0) }
            }
        }
        return frontier
    }

    private func claimedSize(within node: FSNode, at path: String, claimed: Set<String>) -> Int64 {
        node.children.reduce(0) { total, child in
            let childPath = path.appendingPathComponent(child.name)
            let childSize = claimed.contains(childPath)
                ? child.size
                : claimedSize(within: child, at: childPath, claimed: claimed)
            return total + childSize
        }
    }

    // MARK: - Building items

    private func item(for match: Match, size: Int64, claimed: Set<String>) -> StorageItem {
        let name = match.rule.title.name(for: match.path, context: context)
        let category = match.rule.category
        let classification = ClassificationContext(category: category, claimed: claimed)
        let children: [StorageItem]? = switch match.rule.children {
        case let .named(namer):
            namedChildren(of: match.node, at: match.path, total: size, namer: namer, classification: classification)
        case .folderTree:
            folderTree(match.node, at: match.path, total: size, classification: classification, compressChains: false)
        case nil:
            nil
        }
        return StorageItem(
            id: match.path,
            title: name.title,
            subtitle: name.subtitle,
            path: match.path,
            size: size,
            category: category,
            about: match.rule.about,
            flags: name.flags,
            isFile: !match.node.isDirectory,
            children: children
        )
    }

    private func namedChildren(
        of node: FSNode, at path: String, total: Int64, namer: Namer, classification: ClassificationContext
    ) -> [StorageItem]? {
        let children = unclaimedChildren(of: node, at: path, claimed: classification.claimed).map { entry in
            let name = namer.name(for: entry.path, context: context)
            return StorageItem(
                id: entry.path, title: name.title, subtitle: name.subtitle, path: entry.path, size: entry.size,
                category: classification.category, flags: name.flags, isFile: !entry.node.isDirectory, children: nil
            )
        }
        return withRemainder(children, total: total, path: path, category: classification.category)
    }

    private func folderTree(
        _ node: FSNode, at path: String, total: Int64, classification: ClassificationContext, compressChains: Bool
    ) -> [StorageItem]? {
        let children = unclaimedChildren(of: node, at: path, claimed: classification.claimed).map { entry in
            var item = StorageItem(
                id: entry.path, title: entry.node.name, path: entry.path, size: entry.size,
                category: classification.category, isFile: !entry.node.isDirectory,
                children: folderTree(
                    entry.node, at: entry.path, total: entry.size, classification: classification,
                    compressChains: compressChains
                )
            )
            if compressChains {
                item = collapsingSingleChildChain(item)
            }
            return item
        }
        return withRemainder(children, total: total, path: path, category: classification.category)
    }

    private func unclaimedChildren(of node: FSNode, at path: String, claimed: Set<String>) -> [UnclaimedChild] {
        node.children.compactMap { child in
            let childPath = path.appendingPathComponent(child.name)
            guard !claimed.contains(childPath) else { return nil }
            let size = child.size - claimedSize(within: child, at: childPath, claimed: claimed)
            return size >= minimumSize ? UnclaimedChild(node: child, path: childPath, size: size) : nil
        }
    }

    private func withRemainder(
        _ children: [StorageItem], total: Int64, path: String, category: StorageCategory
    ) -> [StorageItem]? {
        guard !children.isEmpty else { return nil }
        let remainder = total - children.reduce(0) { $0 + $1.size }
        guard remainder >= minimumSize else { return children.sortedBySize }
        let rest = StorageItem(
            id: path + "#remainder", kind: .remainder, title: "Smaller items", path: path, size: remainder,
            category: category, children: nil
        )
        return (children + [rest]).sortedBySize
    }

    /// `Users` › `simon` › `Code` with nothing else alongside becomes a single `Users/simon/Code` row.
    private func collapsingSingleChildChain(_ item: StorageItem) -> StorageItem {
        guard let only = item.children?.first, item.children?.count == 1 else { return item }
        var merged = StorageItem(
            id: only.id, title: item.title.appendingPathComponent(only.title), path: only.path, size: only.size,
            category: only.category, isFile: only.isFile, children: only.children
        )
        merged = collapsingSingleChildChain(merged)
        return merged
    }

    private func categoryItem(
        _ category: StorageCategory, entries: [(group: String?, item: StorageItem)]
    ) -> StorageItem {
        var groups: [String: [StorageItem]] = [:]
        var ungrouped: [StorageItem] = []
        for entry in entries {
            if let group = entry.group {
                groups[group, default: []].append(entry.item)
            } else {
                ungrouped.append(entry.item)
            }
        }

        let groupItems = groups.map { title, items in
            StorageItem(
                id: "group:\(category.rawValue):\(title)", kind: .group, title: title,
                size: items.reduce(0) { $0 + $1.size }, category: category, children: items.sortedBySize
            )
        }
        let children = (groupItems + ungrouped).sortedBySize
        return StorageItem(
            id: "category:\(category.rawValue)", kind: .category, title: category.title,
            size: children.reduce(0) { $0 + $1.size }, category: category, children: children
        )
    }
}
