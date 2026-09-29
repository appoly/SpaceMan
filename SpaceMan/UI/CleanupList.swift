import AppKit
import Observation

struct CleanupEntry: Identifiable, Hashable {
    let path: String
    let title: String
    var size: Int64

    var id: String { path }
}

/// What a clean-up changed on disk, for updating the scan without repeating it.
nonisolated struct CleanupOutcome: Sendable {
    let failures: [CleanupFailure]
    /// Items gone from where they were (deleted or moved to the Trash), excluding the Trash itself.
    let removedPaths: [String]
    /// Whether the Trash's contents changed: emptied, or given the moved items.
    let trashChanged: Bool
}

nonisolated struct CleanupFailure: Identifiable, Sendable {
    let path: String
    let message: String

    var id: String { path }

    var isApp: Bool {
        path.hasSuffix(".app")
    }
}

@Observable
final class CleanupList {
    enum Inclusion {
        case included
        case includedViaAncestor(String)
        case excluded
    }

    private(set) var entries: [CleanupEntry] = []
    private(set) var isCleaning = false
    private var index: CleanupIndex?
    private let recycle: ([URL]) async -> Void

    /// Finder performs the move by default, so it can remove other apps (App Management) and ask for a password.
    init(recycle: @escaping ([URL]) async -> Void = { _ = try? await NSWorkspace.shared.recycle($0) }) {
        self.recycle = recycle
    }

    var includesTrash: Bool {
        entries.contains { $0.path == index?.trashPath }
    }

    var includesItemsBesidesTrash: Bool {
        entries.contains { $0.path != index?.trashPath }
    }

    /// Checked live rather than from the scan, in case the permission was granted since.
    var appsBlockedByAppManagement: [CleanupEntry] {
        entries.filter { CleanupIndex.isBlockedByAppManagement($0.path) }
    }

    var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.size }
    }

    /// Keeps entries across rescans, dropping any that are gone or no longer deletable and refreshing sizes.
    func update(index: CleanupIndex) {
        self.index = index
        entries = entries.compactMap { entry in
            guard index.eligibility(ofPath: entry.path) == .eligible, let size = index.diskSizes[entry.path] else {
                return nil
            }
            return CleanupEntry(path: entry.path, title: entry.title, size: size)
        }
    }

    func eligibility(of item: StorageItem) -> CleanupEligibility {
        index?.eligibility(of: item) ?? .notAFolder
    }

    func inclusion(of path: String) -> Inclusion {
        if entries.contains(where: { $0.path == path }) {
            return .included
        }
        if let ancestor = entries.first(where: { path.hasPrefix($0.path + "/") }) {
            return .includedViaAncestor(ancestor.path)
        }
        return .excluded
    }

    func toggle(_ item: StorageItem) {
        guard let path = item.path else { return }
        switch inclusion(of: path) {
        case .included: remove(path)
        case .excluded: add(item)
        case .includedViaAncestor: break
        }
    }

    /// Adding a folder subsumes anything already listed inside it.
    func add(_ item: StorageItem) {
        guard eligibility(of: item) == .eligible, let path = item.path, let size = index?.diskSizes[path] else {
            return
        }
        entries.removeAll { $0.path.hasPrefix(path + "/") }
        entries.append(CleanupEntry(path: path, title: item.title, size: size))
    }

    func remove(_ path: String) {
        entries.removeAll { $0.path == path }
    }

    /// Entries that couldn't be removed stay listed.
    func cleanUp(permanently: Bool) async -> CleanupOutcome {
        isCleaning = true
        defer { isCleaning = false }
        let trashPath = index?.trashPath
        // Captured first so items moved to the Trash below aren't then permanently deleted with it.
        let emptiesTrash = includesTrash
        let trashContents = emptiesTrash ? trashPath.map(Self.contents(ofTrashAt:)) ?? [] : []
        let paths = entries.map(\.path).filter { $0 != trashPath }
        var failures = permanently ? await delete(paths) : await moveToTrash(paths)
        if let trashPath, emptiesTrash {
            failures += await emptyTrash(trashContents, at: trashPath)
        }
        let failedPaths = Set(failures.map(\.path))
        let removedPaths = paths.filter { !failedPaths.contains($0) }
        entries.removeAll { !failedPaths.contains($0.path) }
        return CleanupOutcome(
            failures: failures,
            removedPaths: removedPaths,
            trashChanged: emptiesTrash || (!permanently && !removedPaths.isEmpty)
        )
    }

    private static func contents(ofTrashAt trashPath: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: trashPath)) ?? []
        return names.map { trashPath.appendingPathComponent($0) }
    }

    /// What's in the Trash is already on its way out, so it's deleted whichever way the rest is cleaned up.
    private func emptyTrash(_ contents: [String], at trashPath: String) async -> [CleanupFailure] {
        let failures = await delete(contents)
        return failures.isEmpty ? [] : [CleanupFailure(
            path: trashPath, message: "\(failures.count) items in the Trash couldn't be deleted."
        )]
    }

    private func delete(_ paths: [String]) async -> [CleanupFailure] {
        await Task.detached {
            paths.compactMap { path -> CleanupFailure? in
                do {
                    try FileManager.default.removeItem(atPath: path)
                    return nil
                } catch {
                    let hint = path.hasSuffix(".app") ? Self.appManagementHint : ""
                    return CleanupFailure(path: path, message: error.localizedDescription + hint)
                }
            }
        }.value
    }

    private func moveToTrash(_ paths: [String]) async -> [CleanupFailure] {
        // Finder's recycle throws if any item fails, discarding the rest, so check what's actually still there.
        await recycle(paths.map { URL(filePath: $0) })
        return paths.filter { FileManager.default.fileExists(atPath: $0) }.map {
            CleanupFailure(path: $0, message: "Finder couldn't move it to the Trash.")
        }
    }

    private nonisolated static let appManagementHint =
        " Deleting apps needs App Management permission (System Settings › Privacy & Security › App Management)."
}
