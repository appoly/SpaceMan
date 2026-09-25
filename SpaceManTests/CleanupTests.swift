import Foundation
import Testing
@testable import SpaceMan

struct CleanupIndexTests {
    private let index = CleanupIndex(
        home: "/Users/test",
        diskSizes: [
            "/Users/test/Library": 100, "/Users/test/Library/Caches": 60, "/Users/test/Library/Caches/App": 60,
            "/Users/test/Code/Project": 40, "/Users/test/Code/Project/build": 30, "/Applications/Root-owned.app": 10,
            "/private/var/folders/ab/cdef/T": 5, "/private/var/folders/ab/cdef/T/junk": 5
        ],
        deletablePaths: [
            "/Users/test/Library", "/Users/test/Library/Caches", "/Users/test/Library/Caches/App",
            "/Users/test/Code/Project", "/Users/test/Code/Project/build", "/private/var/folders/ab/cdef/T",
            "/private/var/folders/ab/cdef/T/junk"
        ]
    )

    private func entry(_ path: String, size: Int64, kind: StorageItem.Kind = .entry) -> StorageItem {
        StorageItem(id: path, kind: kind, title: path, path: path, size: size, category: .other)
    }

    @Test func concreteDeletableFoldersAreEligible() {
        #expect(index.eligibility(of: entry("/Users/test/Library/Caches/App", size: 60)) == .eligible)
        #expect(index.eligibility(of: entry("/private/var/folders/ab/cdef/T/junk", size: 5)) == .eligible)
    }

    @Test func accountAndSystemStructureIsProtected() {
        #expect(index.eligibility(of: entry("/Users/test/Library", size: 100)) == .protected)
        #expect(index.eligibility(of: entry("/Users/test/Library/Caches", size: 60)) == .protected)
        #expect(index.eligibility(of: entry("/private/var/folders/ab/cdef/T", size: 5)) == .protected)
    }

    @Test func catchAllsThatExcludeListedChildrenAreRefused() {
        #expect(index.eligibility(of: entry("/Users/test/Code/Project", size: 10)) == .partial)
    }

    @Test func groupingsAndUnwritableItemsAreRefused() {
        #expect(index.eligibility(of: entry("/Users/test/Code/Project", size: 40, kind: .group)) == .notAFolder)
        #expect(index.eligibility(of: entry("/Users/test/Code/Project#remainder", size: 5)) == .notAFolder)
        #expect(index.eligibility(of: entry("/Applications/Root-owned.app", size: 10)) == .noPermission)
    }

    @Test func onlyTheRunningAppBundleIsProtectedNotItsEnclosingFolders() {
        let bundle = Bundle.main.bundlePath
        #expect(index.isProtected(bundle))
        #expect(index.isProtected(bundle.appendingPathComponent("Contents")))
        #expect(!index.isProtected(bundle.deletingLastPathComponent))
    }

    @MainActor @Test func addingAFolderSubsumesItsListedDescendants() {
        let list = CleanupList()
        list.update(index: index)
        list.add(entry("/Users/test/Code/Project/build", size: 30))
        list.add(entry("/Users/test/Code/Project", size: 40))

        #expect(list.entries.map(\.path) == ["/Users/test/Code/Project"])
        #expect(list.totalSize == 40)
        let inclusion = list.inclusion(of: "/Users/test/Code/Project/build")
        guard case .includedViaAncestor("/Users/test/Code/Project") = inclusion else {
            Issue.record("Descendant should be included via its ancestor")
            return
        }
    }

    @MainActor @Test func permanentCleanUpDeletesListedFolders() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CleanupTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 10).write(to: folder.appending(path: "file"))
        let path = folder.path
        let list = CleanupList()
        list.update(index: CleanupIndex(home: "/Users/test", diskSizes: [path: 10], deletablePaths: [path]))
        list.add(entry(path, size: 10))

        let failures = await list.cleanUp(permanently: true)

        #expect(failures.isEmpty)
        #expect(list.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @MainActor @Test func cleaningUpTheTrashEmptiesItWhicheverWayTheRestGoes() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "CleanupHome-\(UUID().uuidString)")
        let trash = home.appending(path: ".Trash")
        let oldFolder = trash.appending(path: "old folder")
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try Data(count: 10).write(to: trash.appending(path: "old file"))
        let list = CleanupList()
        list.update(index: CleanupIndex(home: home.path, diskSizes: [trash.path: 10], deletablePaths: [trash.path]))
        list.add(entry(trash.path, size: 10))
        #expect(list.includesTrash)

        let failures = await list.cleanUp(permanently: false)

        #expect(failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: trash.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    @MainActor @Test func itemsMovedToTheTrashSurviveEmptyingItInTheSameCleanUp() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "CleanupHome-\(UUID().uuidString)")
        let trash = home.appending(path: ".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data(count: 10).write(to: trash.appending(path: "already trashed"))
        let other = home.appending(path: "Projects/other")
        let projects = other.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try Data(count: 10).write(to: other)
        let list = CleanupList { urls in
            for url in urls {
                try? FileManager.default.moveItem(at: url, to: trash.appending(path: url.lastPathComponent))
            }
        }
        let sizes = [trash.path: Int64(10), other.path: 10]
        list.update(index: CleanupIndex(home: home.path, diskSizes: sizes, deletablePaths: [trash.path, other.path]))
        list.add(entry(trash.path, size: 10))
        list.add(entry(other.path, size: 10))
        #expect(list.entries.count == 2)

        let failures = await list.cleanUp(permanently: false)

        #expect(failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: trash.appending(path: "other").path))
        #expect(!FileManager.default.fileExists(atPath: trash.appending(path: "already trashed").path))
    }
}
