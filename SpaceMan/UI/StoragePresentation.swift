enum StoragePresentation: String, CaseIterable {
    case list
    case chart

    var title: String {
        switch self {
        case .list: "List"
        case .chart: "Chart"
        }
    }

    var symbol: String {
        switch self {
        case .list: "list.bullet.indent"
        case .chart: "chart.pie"
        }
    }
}
