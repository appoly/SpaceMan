import Foundation
import Testing
@testable import SpaceMan

struct StorageSortTests {
    private func item(
        _ title: String, size: Int64, kind: StorageItem.Kind = .entry, identifiedAs: String? = nil
    ) -> StorageItem {
        StorageItem(
            id: title, kind: kind, title: title, path: "/\(title)", size: size, category: .other,
            identifiedAs: identifiedAs
        )
    }

    @Test func namesSortEitherWayWithSmallerItemsLast() {
        let items = [
            item("Smaller items", size: 50, kind: .remainder), item("beta", size: 10), item("Alpha", size: 20)
        ]
        #expect(items.sorted(using: StorageSort(column: .name, order: .forward)).map(\.title) == [
            "Alpha", "beta", "Smaller items"
        ])
        #expect(items.sorted(using: StorageSort(column: .name, order: .reverse)).map(\.title) == [
            "beta", "Alpha", "Smaller items"
        ])
    }

    @Test func itemsWithoutAValueGoLastLargestFirst() {
        let items = [
            item("a", size: 10), item("b", size: 30), item("c", size: 5, identifiedAs: "Xcode"),
            item("d", size: 1, identifiedAs: "DerivedData")
        ]
        #expect(items.sorted(using: StorageSort(column: .identifiedAs, order: .reverse)).map(\.title) == [
            "c", "d", "b", "a"
        ])
    }

    @Test func sizeSortsDescendingByDefault() {
        let items = [item("a", size: 10), item("b", size: 30), item("c", size: 20)]
        #expect(items.sorted(using: StorageSort.largestFirst).map(\.title) == ["b", "c", "a"])
    }
}
