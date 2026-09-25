import AppKit
import SwiftUI

struct ItemInspector: View {
    let item: StorageItem?

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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

                    Text(item.size.formatted(.byteCount(style: .file)))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()

                    if let about = item.about {
                        Text(LocalizedStringKey(about))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(item.flags, id: \.self) { flag in
                        Label(LocalizedStringKey(flag), systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .fixedSize(horizontal: false, vertical: true)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right", description: Text("Select an item to see what it is."))
        }
    }
}
