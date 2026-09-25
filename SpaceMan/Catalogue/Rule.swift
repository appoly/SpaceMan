nonisolated enum ChildListing: Sendable {
    /// One level of children, each named with the given namer.
    case named(Namer)
    /// The retained folder hierarchy beneath the item, named by folder.
    case folderTree
}

/// Claims every path matching `pattern` for `category`. When patterns overlap, the deeper match wins, then the rule
/// listed first in the catalogue.
nonisolated struct Rule: Sendable {
    let category: StorageCategory
    let group: String?
    /// Absolute path, optionally starting with `~`. Components may contain `fnmatch(3)` wildcards.
    let pattern: String
    let title: Namer
    let children: ChildListing?
    let about: String?

    init(
        _ category: StorageCategory,
        _ group: String? = nil,
        _ pattern: String,
        _ title: Namer,
        children: ChildListing? = nil,
        about: String? = nil
    ) {
        self.category = category
        self.group = group
        self.pattern = pattern
        self.title = title
        self.children = children
        self.about = about
    }

    init(
        _ category: StorageCategory,
        _ group: String? = nil,
        _ pattern: String,
        _ title: String,
        children: ChildListing? = nil,
        about: String? = nil
    ) {
        self.init(category, group, pattern, .fixed(title), children: children, about: about)
    }
}
