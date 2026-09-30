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
    /// Passed explicitly: cells created as rows expand don't reliably inherit the SwiftUI environment.
    let cleanup: CleanupList

    var body: some View {
        Table(of: StorageItem.self, selection: $selection) {
            TableColumn("Name") { item in
                NameCell(item: item, mode: mode, cleanup: cleanup)
            }
            .width(min: 180, ideal: 420)

            TableColumn(mode == .categories ? "Location" : "Identified as") { item in
                SecondaryCell(item: item, mode: mode)
            }
            .width(min: 100, ideal: 280)

            TableColumn("Size") { item in
                SizeCell(
                    size: item.size,
                    scale: largestTopLevelSize,
                    totalUsed: totalUsed,
                    excludesItemsListedSeparately: cleanup.excludesItemsListedSeparately(item)
                )
            }
            .width(120)
        } rows: {
            StorageRows(items: items, expanded: $expanded)
        }
        .background(TableViewConfigurator())
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
            if let id = ids.first, let item = items.item(withID: id) {
                if let path = item.path {
                    Button("Reveal in Finder") { NSWorkspace.shared.revealInFinder(path) }
                    Button("Copy Path") { NSPasteboard.general.copy(path) }
                }
                cleanupMenuItems(for: item)
            }
        } primaryAction: { ids in
            if let id = ids.first {
                toggleExpansion(of: id)
            }
        }
    }

    @ViewBuilder
    private func cleanupMenuItems(for item: StorageItem) -> some View {
        let eligibility = cleanup.eligibility(of: item)
        if item.path != nil, eligibility.showsCheckbox || item.children != nil {
            Divider()
        }
        if eligibility.showsCheckbox, let path = item.path {
            switch cleanup.inclusion(of: path) {
            case .included:
                Button("Remove from Clean Up") { cleanup.remove(path) }
            case .includedViaAncestor:
                Button("Included via an Enclosing Folder") {}.disabled(true)
            case .excluded:
                Button("Add to Clean Up") { cleanup.add(item) }
                    .disabled(eligibility != .eligible)
            }
        }
        if item.children != nil {
            Button("Select All for Clean Up") { cleanup.addAll(in: item) }
                .disabled(cleanup.addableItems(in: item).isEmpty)
        }
    }

    private var largestTopLevelSize: Int64 {
        items.map(\.size).max() ?? 0
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

private struct CleanupCheckbox: View {
    let item: StorageItem
    let cleanup: CleanupList

    var body: some View {
        let eligibility = cleanup.eligibility(of: item)
        if eligibility.showsCheckbox, let path = item.path {
            let inclusion = cleanup.inclusion(of: path)
            Toggle("Include in Clean Up", isOn: Binding {
                switch inclusion {
                case .included, .includedViaAncestor: true
                case .excluded: false
                }
            } set: { _ in
                cleanup.toggle(item)
            })
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!isToggleable(eligibility, inclusion))
            .help(helpText(eligibility, inclusion))
        }
    }

    private func isToggleable(_ eligibility: CleanupEligibility, _ inclusion: CleanupList.Inclusion) -> Bool {
        switch inclusion {
        case .included: true
        case .includedViaAncestor: false
        case .excluded: eligibility == .eligible
        }
    }

    private func helpText(_ eligibility: CleanupEligibility, _ inclusion: CleanupList.Inclusion) -> String {
        switch inclusion {
        case .included: "Included in Clean Up"
        case let .includedViaAncestor(ancestor): "Included via \(ancestor.abbreviatingWithTilde)"
        case .excluded: eligibility.reason ?? "Add to Clean Up"
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

/// The tick box lives in the name cell because the outline's indentation and disclosure arrows always occupy the
/// table's first column.
private struct NameCell: View {
    let item: StorageItem
    let mode: StorageViewMode
    let cleanup: CleanupList

    var body: some View {
        HStack(spacing: 6) {
            CleanupCheckbox(item: item, cleanup: cleanup)
                .frame(width: 14)
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

/// Bars are scaled to the largest top-level row so the column's width is used; the tooltip gives the disk share.
private struct SizeCell: View {
    private static let shareFormat = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(1))

    let size: Int64
    let scale: Int64
    let totalUsed: Int64
    let excludesItemsListedSeparately: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                Text(size.formatted(.byteCount(style: .file)))
                    .monospacedDigit()
                    .frame(width: 76, alignment: .trailing)
                Text(verbatim: "*")
                    .opacity(excludesItemsListedSeparately ? 1 : 0)
            }
            .fixedSize()
            GeometryReader { proxy in
                Capsule()
                    .fill(.tint.opacity(0.6))
                    .frame(width: max(2, proxy.size.width * fraction(of: scale)))
            }
            .frame(height: 6)
        }
        .help(helpText)
    }

    private var helpText: String {
        let share = totalUsed > 0 ? "\(fraction(of: totalUsed).formatted(Self.shareFormat)) of used space" : ""
        guard excludesItemsListedSeparately else { return share }
        return share + "\n* Excludes items inside this folder that are listed separately"
    }

    private func fraction(of total: Int64) -> Double {
        total > 0 ? min(1, Double(size) / Double(total)) : 0
    }
}
