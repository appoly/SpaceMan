import SwiftUI

struct UsageBar: View {
    let categories: [StorageItem]
    let capacity: DiskCapacity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(capacity.used.formatted(.byteCount(style: .file))) used")
                    .font(.title2.bold())
                Text("of \(capacity.total.formatted(.byteCount(style: .file)))")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(capacity.availableIncludingPurgeable.formatted(.byteCount(style: .file))) available")
                    .font(.title2.bold())
            }

            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(categories) { category in
                        category.category.colour
                            .frame(width: width(of: category.size, in: proxy.size.width))
                            .help("\(category.title): \(category.size.formatted(.byteCount(style: .file)))")
                    }
                    Color.secondary.opacity(0.15)
                }
                .clipShape(.rect(cornerRadius: 4))
            }
            .frame(height: 14)

            FlowLegend(categories: categories)
        }
    }

    private func width(of size: Int64, in totalWidth: CGFloat) -> CGFloat {
        guard capacity.total > 0 else { return 0 }
        return max(1, totalWidth * CGFloat(size) / CGFloat(capacity.total))
    }
}

private struct FlowLegend: View {
    let categories: [StorageItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { entries }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], alignment: .leading, spacing: 4
            ) { entries }
        }
        .font(.caption)
    }

    private var entries: some View {
        ForEach(categories) { category in
            HStack(spacing: 4) {
                Circle().fill(category.category.colour).frame(width: 8, height: 8)
                Text(category.title)
                Text(category.size.formatted(.byteCount(style: .file))).foregroundStyle(.secondary)
            }
            .fixedSize()
        }
    }
}
