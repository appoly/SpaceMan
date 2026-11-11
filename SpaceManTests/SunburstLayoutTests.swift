import Foundation
import Testing
@testable import SpaceMan

struct SunburstLayoutTests {
    private func item(_ title: String, size: Int64, children: [StorageItem]? = nil) -> StorageItem {
        StorageItem(id: title, title: title, path: "/\(title)", size: size, category: .other, children: children)
    }

    @Test func topLevelAddsUnlistedAndFreeSpaceToFillTheDisk() {
        let layout = SunburstLayout(
            items: [item("a", size: 30), item("b", size: 10)], total: 100, freeSpace: 50, maxDepth: 3,
            minimumFraction: 0
        )
        #expect(layout.segments.map(\.id) == ["a", "b", "chart:unlisted", "chart:free"])
        #expect(layout.segments.map(\.start) == [0, 0.3, 0.4, 0.5])
        #expect(layout.segments.last?.end == 1)
        #expect(layout.itemsEnd == 0.4)
    }

    @Test func childrenFillTheirParentsArc() {
        let parent = item("parent", size: 40, children: [item("x", size: 10), item("y", size: 30)])
        let layout = SunburstLayout(items: [parent, item("z", size: 40)], total: 80, maxDepth: 3, minimumFraction: 0)
        let children = layout.segments.filter { $0.parentID == "parent" }
        #expect(children.map(\.id) == ["y", "x"])
        #expect(children.map(\.depth) == [2, 2])
        #expect(children.map(\.start) == [0, 0.375])
        #expect(children.last?.end == 0.5)
    }

    @Test func thinArcsAndRingsBeyondTheLimitAreDropped() {
        let deep = item("a", size: 99, children: [item("b", size: 99, children: [item("c", size: 99)])])
        let layout = SunburstLayout(
            items: [deep, item("tiny", size: 1)], total: 100, maxDepth: 2, minimumFraction: 0.05
        )
        #expect(layout.segments.map(\.id) == ["a", "b"])
        #expect(layout.depth == 2)
    }

    @Test func lineageRunsFromTheTopLevelDown() {
        let tree = [
            item("x", size: 5), item("a", size: 10, children: [item("b", size: 10, children: [item("c", size: 10)])])
        ]
        #expect(tree.lineage(to: "c") == ["a", "b", "c"])
        #expect(tree.lineage(to: "missing") == nil)
    }
}
