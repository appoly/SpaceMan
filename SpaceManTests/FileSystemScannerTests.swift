import Foundation
import Testing
@testable import SpaceMan

struct FileSystemScannerTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: "big/nested"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: root.appending(path: "small"), withIntermediateDirectories: true)
        try Data(count: 3_000_000).write(to: root.appending(path: "big/nested/blob"))
        try Data(count: 1_000).write(to: root.appending(path: "small/tiny"))
    }

    private func scan(threshold: Int64 = 1_000_000) async -> FSNode {
        await FileSystemScanner(retainThreshold: threshold, stats: ScanStats()).scan(path: root.path)
    }

    private func allocatedSize(_ relativePath: String) throws -> Int64 {
        let values = try root.appending(path: relativePath).resourceValues(forKeys: [.fileAllocatedSizeKey])
        return Int64(try #require(values.fileAllocatedSize))
    }

    @Test func totalsMatchAllocatedSizesAndCountHardLinksOnce() async throws {
        try FileManager.default.linkItem(
            at: root.appending(path: "big/nested/blob"), to: root.appending(path: "small/blob-link")
        )
        let node = await scan()
        let expected = try allocatedSize("big/nested/blob") + allocatedSize("small/tiny")
        #expect(node.size == expected)
    }

    @Test func retainsOnlyEntriesAboveThreshold() async throws {
        let node = await scan()
        #expect(node.children.map(\.name) == ["big"])
        let nested = try #require(node.children.first?.children.first)
        #expect(nested.name == "nested")
        #expect(nested.children.map(\.name) == ["blob"])
        #expect(nested.children.first?.isDirectory == false)
    }
}
