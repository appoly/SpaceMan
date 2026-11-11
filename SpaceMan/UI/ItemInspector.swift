import AppKit
import SwiftUI

enum InspectorSubject {
    case item(StorageItem)
    /// Space that isn't an item, such as the whole disk or its free space.
    case summary(title: String, size: Int64)
}

extension InspectorSubject {
    var item: StorageItem? {
        switch self {
        case let .item(item): item
        case .summary: nil
        }
    }
}

struct ItemInspector: View {
    let subject: InspectorSubject?
    let contents: [ContentsRow]
    @Binding var highlightedRowID: String?
    let open: ((StorageItem) -> Void)?

    var body: some View {
        if let subject {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch subject {
                    case let .item(item):
                        ItemHeading(item: item)
                        size(item.size)
                        ItemDetails(item: item)
                    case let .summary(title, size):
                        Text(title)
                            .font(.title3.bold())
                        self.size(size)
                    }
                    if !contents.isEmpty {
                        ContentsList(rows: contents, highlightedID: $highlightedRowID, open: open)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No Selection", systemImage: "sidebar.right", description: Text("Select an item to see what it is.")
            )
        }
    }

    private func size(_ size: Int64) -> some View {
        Text(size.formatted(.byteCount(style: .file)))
            .font(.largeTitle.weight(.semibold))
            .monospacedDigit()
    }
}

struct ItemHeading: View {
    let item: StorageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(item.category.title, systemImage: item.category.symbol)
                .font(.caption)
                .foregroundStyle(item.category.colour)
            Text(item.title)
                .font(.title3.bold())
                .textSelection(.enabled)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Everything about the item below its heading and size.
struct ItemDetails: View {
    let item: StorageItem
    var showsUnreadableFolders = true

    var body: some View {
        if let about = item.about {
            Text(LocalizedStringKey(about))
                .fixedSize(horizontal: false, vertical: true)
        }

        ForEach(item.flags, id: \.self) { flag in
            Label(LocalizedStringKey(flag), systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .fixedSize(horizontal: false, vertical: true)
        }

        if showsUnreadableFolders, !item.unreadablePaths.isEmpty {
            UnreadableFolders(paths: item.unreadablePaths)
        }

        if let path = item.path {
            VStack(alignment: .leading, spacing: 8) {
                Text(path)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button("Reveal in Finder") { NSWorkspace.shared.revealInFinder(path) }
                    Button("Copy Path") { NSPasteboard.general.copy(path) }
                }
            }
        }
    }
}

private struct UnreadableFolders: View {
    let paths: [String]

    var body: some View {
        DisclosureGroup("\(paths.count) folders couldn't be read") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(paths, id: \.self) { path in
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Copy List") { NSPasteboard.general.copy(paths.joined(separator: "\n")) }
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
