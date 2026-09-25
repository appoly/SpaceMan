import AppKit
import SwiftUI

struct StorageTable: View {
    let categories: [StorageItem]
    let totalUsed: Int64
    @Binding var selection: StorageItem.ID?

    var body: some View {
        Table(categories, children: \.children, selection: $selection) {
            TableColumn("Name") { item in
                NameCell(item: item)
            }
            .width(min: 280, ideal: 420)

            TableColumn("Size") { item in
                SizeCell(size: item.size, share: totalUsed > 0 ? Double(item.size) / Double(totalUsed) : 0)
            }
            .width(min: 150, ideal: 180, max: 240)

            TableColumn("Location") { item in
                Text(item.kind == .remainder ? "" : item.path?.abbreviatingWithTilde ?? "")
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .help(item.path ?? "")
            }
        }
        .contextMenu(forSelectionType: StorageItem.ID.self) { ids in
            if let id = ids.first, let path = categories.item(withID: id)?.path {
                Button("Reveal in Finder") { NSWorkspace.shared.revealInFinder(path) }
                Button("Copy Path") { NSPasteboard.general.copy(path) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let path = categories.item(withID: id)?.path {
                NSWorkspace.shared.revealInFinder(path)
            }
        }
    }
}

private struct NameCell: View {
    let item: StorageItem

    var body: some View {
        HStack(spacing: 6) {
            ItemIcon(item: item)
            Text(item.title)
                .fontWeight(item.kind == .category ? .semibold : .regular)
                .foregroundStyle(item.kind == .remainder ? .secondary : .primary)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if item.flagCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(item.flags.first ?? "Contains items needing attention")
            }
        }
        .lineLimit(1)
    }
}

private struct ItemIcon: View {
    let item: StorageItem

    var body: some View {
        switch item.kind {
        case .category:
            Image(systemName: item.category.symbol)
                .foregroundStyle(item.category.colour)
                .frame(width: 16)
        case .group:
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(item.category.colour)
                .frame(width: 16)
        case .remainder:
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
                .frame(width: 16)
        case .entry:
            if let path = item.path, path.hasSuffix(".app") {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: item.isFile ? "doc" : "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
        }
    }
}

private struct SizeCell: View {
    let size: Int64
    let share: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(size.formatted(.byteCount(style: .file)))
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)
            GeometryReader { proxy in
                Capsule()
                    .fill(.tint.opacity(0.6))
                    .frame(width: max(2, proxy.size.width * share))
            }
            .frame(height: 6)
        }
    }
}
