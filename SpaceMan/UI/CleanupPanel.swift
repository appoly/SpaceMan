import SwiftUI

struct CleanupPanel: View {
    let cleanup: CleanupList
    let cleanUp: (_ permanently: Bool) async -> [CleanupFailure]
    @State private var isConfirming = false
    @State private var failures: [CleanupFailure] = []
    /// Sizes the list to its rows up to a cap. `fixedSize` would instead demand the rows' height at whatever
    /// width macOS proposes while computing the window's minimum size, pinning the window to full height.
    @State private var entriesHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Clean Up").font(.headline)
                Spacer()
                Text(cleanup.totalSize.formatted(.byteCount(style: .file)))
                    .font(.headline)
                    .monospacedDigit()
            }

            if cleanup.entries.isEmpty {
                Text("Tick items in the list to add them here.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(cleanup.entries) { entry in
                            EntryRow(entry: entry) { cleanup.remove(entry.path) }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { entriesHeight = $0 }
                }
                .frame(height: min(entriesHeight, 180))
            }

            Button {
                isConfirming = true
            } label: {
                if cleanup.isCleaning {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                } else {
                    Text("Clean Up…").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(cleanup.entries.isEmpty || cleanup.isCleaning)
        }
        .padding()
        .confirmationDialog(confirmationTitle, isPresented: $isConfirming) {
            switch (cleanup.includesTrash, cleanup.includesItemsBesidesTrash) {
            case (true, false):
                Button("Empty Trash", role: .destructive) { run(permanently: true) }
            case (true, true):
                Button("Empty Trash, Move Others to Trash") { run(permanently: false) }
                Button("Delete All Immediately", role: .destructive) { run(permanently: true) }
            case (false, _):
                Button("Move to Trash") { run(permanently: false) }
                Button("Delete Immediately", role: .destructive) { run(permanently: true) }
            }
        } message: {
            Text(confirmationMessage)
        }
        .alert("Some items couldn't be removed", isPresented: hasFailures) {
            Button("OK") { failures = [] }
        } message: {
            Text(failures.map { "\($0.path.abbreviatingWithTilde): \($0.message)" }.joined(separator: "\n\n"))
        }
    }

    private var hasFailures: Binding<Bool> {
        Binding { !failures.isEmpty } set: { isPresented in
            if !isPresented {
                failures = []
            }
        }
    }

    private var confirmationMessage: String {
        let trash = "Everything currently in the Trash will be deleted permanently. This can't be undone."
        let others = "Moving to the Trash frees the space once you empty it. Deleting immediately can't be undone."
        switch (cleanup.includesTrash, cleanup.includesItemsBesidesTrash) {
        case (true, false): return trash
        case (true, true): return trash + "\n\nFor the other items: " + others
        case (false, _): return others
        }
    }

    private var confirmationTitle: String {
        let count = cleanup.entries.count
        let size = cleanup.totalSize.formatted(.byteCount(style: .file))
        return "Clean up \(count) \(count == 1 ? "item" : "items") (\(size))?"
    }

    private func run(permanently: Bool) {
        Task {
            failures = await cleanUp(permanently)
        }
    }
}

private struct EntryRow: View {
    let entry: CleanupEntry
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).lineLimit(1)
                Text(entry.path.abbreviatingWithTilde)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(entry.size.formatted(.byteCount(style: .file)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .help(entry.path)
    }
}

/// Why the selected row can't be ticked, so a disabled tick box is never a mystery.
struct CleanupEligibilityNote: View {
    let item: StorageItem?
    let cleanup: CleanupList

    var body: some View {
        if let note {
            Label(note, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private var note: String? {
        guard let item, let path = item.path else { return nil }
        let eligibility = cleanup.eligibility(of: item)
        guard eligibility.showsCheckbox else { return nil }
        if case let .includedViaAncestor(ancestor) = cleanup.inclusion(of: path) {
            return "Already included via \(ancestor.abbreviatingWithTilde)."
        }
        return eligibility.reason
    }
}
