import SwiftUI

struct ContentView: View {
    @State private var model = ScanModel()
    @State private var selection: StorageItem.ID?
    @State private var showsInspector = true

    var body: some View {
        content
            .frame(minWidth: 760, minHeight: 480)
            .inspector(isPresented: $showsInspector) {
                ItemInspector(item: selection.flatMap { model.result?.categories.item(withID: $0) })
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(model.result == nil ? "Scan" : "Rescan", systemImage: "arrow.clockwise") {
                        model.scan()
                    }
                    .disabled(model.isScanning)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Inspector", systemImage: "sidebar.right") { showsInspector.toggle() }
                }
            }
            .task {
                if case .idle = model.phase {
                    model.scan()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView("Ready to Scan", systemImage: "internaldrive")
        case let .scanning(itemCount, started):
            ScanProgressView(itemCount: itemCount, started: started)
        case let .finished(result):
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.hasFullDiskAccess {
                        FullDiskAccessBanner(deniedFolderCount: result.deniedFolderCount)
                    }
                    if let capacity = result.capacity {
                        UsageBar(categories: result.categories, capacity: capacity)
                    }
                }
                .padding()

                StorageTable(
                    categories: result.categories,
                    totalUsed: result.capacity?.used ?? result.categories.reduce(0) { $0 + $1.size },
                    selection: $selection
                )
            }
        }
    }
}

private struct ScanProgressView: View {
    let itemCount: Int
    let started: Date

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning…").font(.headline)
            Text("\(itemCount.formatted()) items")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(started, style: .timer)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FullDiskAccessBanner: View {
    let deniedFolderCount: Int
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text("SpaceMan can't see everything").font(.headline)
                Text("\(deniedFolderCount) folders couldn't be read. Grant Full Disk Access, then rescan.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
    }
}
