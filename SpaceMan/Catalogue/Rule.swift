nonisolated enum RuleCondition: Sendable {
    /// Build output of this kind of project, as judged by `BuildFolderDetector`.
    case buildFolder(ProjectKind)

    func isSatisfied(at path: String, context: NamingContext) -> Bool {
        switch self {
        case let .buildFolder(kind): context.buildProject(at: path)?.kind == kind
        }
    }
}

nonisolated enum ChildListing: Sendable {
    /// One level of children, each named with the given namer.
    case named(Namer)
    /// The retained folder hierarchy beneath the item, named by folder.
    case folderTree
}

/// Claims every path matching `pattern` for `category`. When patterns overlap, the deeper match wins, then the rule
/// listed first in the catalogue. A `**` pattern claims only its outermost matches, so nested matches don't hollow
/// out their ancestors.
nonisolated struct Rule: Sendable {
    let category: StorageCategory
    let group: String?
    /// Absolute path, optionally starting with `~`. Components may contain `fnmatch(3)` wildcards and `{a,b}`
    /// alternatives, and a `**` component matches any number of folders.
    let pattern: String
    let title: Namer
    let children: ChildListing?
    let about: String?
    let condition: RuleCondition?

    init(
        _ category: StorageCategory,
        _ group: String? = nil,
        _ pattern: String,
        _ title: Namer,
        children: ChildListing? = nil,
        about: String? = nil,
        condition: RuleCondition? = nil
    ) {
        self.category = category
        self.group = group
        self.pattern = pattern
        self.title = title
        self.children = children
        self.about = about
        self.condition = condition
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
