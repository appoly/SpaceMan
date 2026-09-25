import Darwin
import Foundation

nonisolated enum CleanupEligibility: Sendable, Equatable {
    case eligible
    /// Categories, groups, "Smaller items" and figures that don't correspond to one folder on disk.
    case notAFolder
    /// A catch-all whose folder also holds items listed elsewhere, so deleting it would delete those too.
    case partial
    case protected
    case noPermission

    var showsCheckbox: Bool {
        switch self {
        case .notAFolder: false
        case .eligible, .partial, .protected, .noPermission: true
        }
    }

    var reason: String? {
        switch self {
        case .eligible, .notAFolder: nil
        case .partial: "This folder also contains items listed separately. Select those instead."
        case .protected: "SpaceMan won't delete this folder because macOS or your account relies on it."
        case .noPermission: "You don't have permission to delete this."
        }
    }
}

/// On-disk facts gathered with the scan for deciding what can be cleaned up.
nonisolated struct CleanupIndex: Sendable {
    let home: String
    let diskSizes: [String: Int64]
    let deletablePaths: Set<String>

    static func build(root: FSNode, home: String) -> CleanupIndex {
        var sizes: [String: Int64] = [:]
        var deletable = Set<String>()
        func visit(_ node: FSNode, at path: String) {
            for child in node.children {
                let childPath = path.appendingPathComponent(child.name)
                sizes[childPath] = child.size
                if canDelete(childPath, isDirectory: child.isDirectory) {
                    deletable.insert(childPath)
                }
                visit(child, at: childPath)
            }
        }
        visit(root, at: "/")
        return CleanupIndex(home: home, diskSizes: sizes, deletablePaths: deletable)
    }

    func eligibility(of item: StorageItem) -> CleanupEligibility {
        guard item.kind == .entry, let path = item.path, let diskSize = diskSizes[path] else { return .notAFolder }
        guard item.size >= diskSize else { return .partial }
        return eligibility(ofPath: path)
    }

    func eligibility(ofPath path: String) -> CleanupEligibility {
        guard diskSizes[path] != nil else { return .notAFolder }
        if path != trashPath, isProtected(path) {
            return .protected
        }
        return deletablePaths.contains(path) ? .eligible : .noPermission
    }

    /// Cleaning this up empties it rather than removing the folder itself.
    var trashPath: String {
        home.appendingPathComponent(".Trash")
    }

    func isProtected(_ path: String) -> Bool {
        let parent = path.deletingLastPathComponent
        let appBundle = Bundle.main.bundlePath
        return path.split(separator: "/").count <= 1
            || path == home
            || parent == home
            || parent == home.appendingPathComponent("Library")
            || Self.protectedPaths.contains(path)
            || Self.protectedPaths.contains(parent)
            || isPerUserTemporaryRoot(path)
            || path == appBundle
            || path.hasPrefix(appBundle + "/")
    }

    /// Their direct children are also protected.
    private static let protectedPaths: Set<String> = [
        "/Users", "/Library", "/System/Library", "/opt/homebrew", "/usr/local", "/private/var", "/private/tmp"
    ]

    /// `/private/var/folders/xx/yyyy/{C,T,X}` and above belong to macOS, though their contents are fair game.
    private func isPerUserTemporaryRoot(_ path: String) -> Bool {
        path.hasPrefix("/private/var/folders") && path.split(separator: "/").count <= 6
    }

    /// Unlinking needs write access to the parent (and ownership in sticky folders such as /tmp); emptying a
    /// folder needs write access to it too. Immutable and SIP-restricted items can't be removed at all. Other apps'
    /// bundles report EPERM under App Management protection, but Finder can still move them to the Trash.
    private static func canDelete(_ path: String, isDirectory: Bool) -> Bool {
        var item = stat()
        var parent = stat()
        let parentPath = path.deletingLastPathComponent
        guard lstat(path, &item) == 0, stat(parentPath, &parent) == 0, access(parentPath, W_OK) == 0 else {
            return false
        }
        let blockingFlags = UInt32(SF_RESTRICTED | SF_IMMUTABLE | UF_IMMUTABLE | SF_APPEND | UF_APPEND)
        guard item.st_flags & blockingFlags == 0 else { return false }
        if parent.st_mode & S_ISVTX != 0, item.st_uid != getuid() {
            return false
        }
        guard isDirectory, access(path, W_OK) != 0 else { return true }
        return errno == EPERM && path.hasSuffix(".app")
    }
}
