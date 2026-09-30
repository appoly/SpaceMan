import SwiftUI

/// The inspector's contents laid out across the bottom of the window while the inspector is hidden, without the
/// Clean Up list, which is too tall to fit.
struct DetailsStrip: View {
    let item: StorageItem?
    let cleanup: CleanupList
    let cleanUp: (_ permanently: Bool) async -> [CleanupFailure]
    let showInspector: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let item {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            ItemHeading(item: item)
                            Text(item.size.formatted(.byteCount(style: .file)))
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                        }
                        .frame(width: 200, alignment: .leading)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ItemDetails(item: item, showsUnreadableFolders: false)
                                CleanupEligibilityNote(item: item, cleanup: cleanup, isPadded: false)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                } else {
                    Text("Select an item to see what it is.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            CleanupPanel(cleanup: cleanup, cleanUp: cleanUp, isCompact: true)
                .frame(width: 240)

            Button("Show Inspector", systemImage: "chevron.left", action: showInspector)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show Inspector")
                .padding(.trailing, 12)
        }
        .frame(height: 110)
    }
}
