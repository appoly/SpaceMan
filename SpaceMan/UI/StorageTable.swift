import AppKit
import SwiftUI

enum StorageViewMode: String, CaseIterable {
    case categories
    case folders

    var title: String {
        switch self {
        case .categories: "Categories"
        case .folders: "Folders"
        }
    }

    var symbol: String {
        switch self {
        case .categories: "square.grid.2x2"
        case .folders: "folder"
        }
    }
}

struct StorageTable: View {
    let items: [StorageItem]
    let mode: StorageViewMode
    let totalUsed: Int64
    @Binding var selection: StorageItem.ID?
    @State private var expanded: Set<StorageItem.ID> = []
    @FocusState private var isFocused: Bool

    var body: some View {
        Table(of: StorageItem.self, selection: $selection) {
            TableColumn("Name") { item in
                NameCell(item: item, mode: mode)
            }
            .width(min: 280, ideal: 420)

            TableColumn(mode == .categories ? "Location" : "Identified as") { item in
                SecondaryCell(item: item, mode: mode)
            }

            TableColumn("Size") { item in
                SizeCell(size: item.size, share: totalUsed > 0 ? Double(item.size) / Double(totalUsed) : 0)
            }
            .width(min: 150, ideal: 180, max: 240)
        } rows: {
            StorageRows(items: items, expanded: $expanded)
        }
        .id(mode)
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: selection) {
            NSApp.keyWindow?.reclaimFocusForTable()
        }
        .onKeyPress(.space) {
            guard let selection else { return .ignored }
            toggleExpansion(of: selection)
            return .handled
        }
        .contextMenu(forSelectionType: StorageItem.ID.self) { ids in
            if let id = ids.first, let path = items.item(withID: id)?.path {
                Button("Reveal in Finder") { NSWorkspace.shared.revealInFinder(path) }
                Button("Copy Path") { NSPasteboard.general.copy(path) }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                toggleExpansion(of: id)
            }
        }
    }

    /// Items with children expand or collapse; leaves reveal themselves in Finder instead.
    private func toggleExpansion(of id: StorageItem.ID) {
        guard let item = items.item(withID: id) else { return }
        if item.children != nil {
            if expanded.remove(id) == nil {
                expanded.insert(id)
            }
        } else if let path = item.path {
            NSWorkspace.shared.revealInFinder(path)
        }
    }
}

private struct StorageRows: TableRowContent {
    let items: [StorageItem]
    @Binding var expanded: Set<StorageItem.ID>

    var tableRowBody: some TableRowContent<StorageItem> {
        ForEach(items) { item in
            if let children = item.children {
                DisclosureTableRow(item, isExpanded: $expanded.containing(item.id)) {
                    StorageRows(items: children, expanded: $expanded)
                }
            } else {
                TableRow(item)
            }
        }
    }
}

private struct SecondaryCell: View {
    let item: StorageItem
    let mode: StorageViewMode

    var body: some View {
        switch mode {
        case .categories:
            Text(item.kind == .remainder ? "" : item.path?.abbreviatingWithTilde ?? "")
                .foregroundStyle(.secondary)
                .truncationMode(.middle)
                .lineLimit(1)
                .help(item.path ?? "")
        case .folders:
            Text(item.identifiedAs ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct NameCell: View {
    let item: StorageItem
    let mode: StorageViewMode

    var body: some View {
        HStack(spacing: 6) {
            ItemIcon(item: item, mode: mode)
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
    let mode: StorageViewMode

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
                    .foregroundStyle(folderStyle)
                    .frame(width: 16)
            }
        }
    }
}

private extension ItemIcon {
    /// In the folder view, colour marks what the catalogue recognised.
    var showsCategoryColour: Bool {
        switch mode {
        case .categories: false
        case .folders: item.category != .other
        }
    }

    var folderStyle: AnyShapeStyle {
        showsCategoryColour ? AnyShapeStyle(item.category.colour) : AnyShapeStyle(.secondary)
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
