import Foundation

/// Orders one level of the outline. Items with nothing in the sorted column go last, largest first.
nonisolated struct StorageSort: SortComparator {
    enum Column: Hashable {
        case name
        case location
        case identifiedAs
        case size
    }

    static let largestFirst = StorageSort(column: .size, order: .reverse)

    let column: Column
    var order: SortOrder

    func compare(_ lhs: StorageItem, _ rhs: StorageItem) -> ComparisonResult {
        switch column {
        case .size:
            return ordered(Self.compare(lhs.size, rhs.size))
        case .name, .location, .identifiedAs:
            switch (text(of: lhs), text(of: rhs)) {
            case let (lhsText?, rhsText?):
                let result = lhsText.localizedStandardCompare(rhsText)
                return result == .orderedSame ? Self.largestFirst.compare(lhs, rhs) : ordered(result)
            case (.some, nil): return .orderedAscending
            case (nil, .some): return .orderedDescending
            case (nil, nil): return Self.largestFirst.compare(lhs, rhs)
            }
        }
    }

    /// "Smaller items" has no name of its own, so it stays at the bottom however names are sorted.
    private func text(of item: StorageItem) -> String? {
        let text: String? = switch column {
        case .name: item.kind == .remainder ? nil : item.title
        case .location: item.locationText
        case .identifiedAs: item.identifiedAs
        case .size: nil
        }
        return text?.isEmpty == false ? text : nil
    }

    private func ordered(_ result: ComparisonResult) -> ComparisonResult {
        switch (order, result) {
        case (.forward, _), (.reverse, .orderedSame): result
        case (.reverse, .orderedAscending): .orderedDescending
        case (.reverse, .orderedDescending): .orderedAscending
        }
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame
    }
}

nonisolated extension StorageItem {
    /// Blank for "Smaller items", whose path is the folder it sits in.
    var locationText: String? {
        kind == .remainder ? nil : path?.abbreviatingWithTilde
    }
}
