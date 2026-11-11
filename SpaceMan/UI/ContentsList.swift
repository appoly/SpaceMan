import SwiftUI

struct ContentsRow: Identifiable {
    let id: String
    let title: String
    let size: Int64
    /// The chart segment's colour; `nil` when there's no chart to match.
    let colour: Color?
    /// `nil` for space that isn't an item, such as free space.
    let item: StorageItem?
}

extension ContentsRow {
    init(item: StorageItem, colour: Color? = nil) {
        self.init(id: item.id, title: item.title, size: item.size, colour: colour, item: item)
    }

    var isMuted: Bool {
        switch item?.kind {
        case .remainder, nil: true
        case .category, .group, .entry: false
        }
    }
}

/// What's inside the inspected item, with free and unlisted space set apart beneath.
struct ContentsList: View {
    let rows: [ContentsRow]
    @Binding var highlightedID: String?
    /// `nil` when rows can't be opened, such as while the inspector follows the pointer around the chart.
    let open: ((StorageItem) -> Void)?

    var body: some View {
        let items = rows.filter { $0.item != nil }
        let others = rows.filter { $0.item == nil }
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents")
                .font(.headline)
                .padding(.bottom, 6)
            ForEach(items) { row in
                if let item = row.item, let open {
                    Button { open(item) } label: { label(for: row) }
                        .buttonStyle(.plain)
                } else {
                    label(for: row)
                }
            }
            if !others.isEmpty {
                Divider().padding(.vertical, 4)
                ForEach(others, content: label(for:))
            }
        }
    }

    private func label(for row: ContentsRow) -> some View {
        HStack(spacing: 8) {
            if let colour = row.colour {
                Circle()
                    .fill(colour)
                    .frame(width: 8, height: 8)
            }
            Text(row.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(row.isMuted ? .secondary : .primary)
            Spacer()
            Text(row.size.formatted(.byteCount(style: .file)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.selection.opacity(row.id == highlightedID ? 0.4 : 0), in: .rect(cornerRadius: 4))
        .contentShape(.rect)
        .padding(.horizontal, -6)
        .onHover { isHovering in
            if isHovering {
                highlightedID = row.id
            } else if highlightedID == row.id {
                highlightedID = nil
            }
        }
    }
}
