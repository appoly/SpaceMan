import SwiftUI

struct ContentView: View {
    @State private var model = ScanModel()
    @State private var selection: StorageItem.ID?
    @State private var showsInspector = true
    @AppStorage("viewMode") private var mode = StorageViewMode.categories

    var body: some View {
        content
            .frame(minWidth: 760, minHeight: 480)
            .inspector(isPresented: $showsInspector) {
                let selectedItem = selection.flatMap { model.result?.allItems.item(withID: $0) }
                VStack(spacing: 0) {
                    ItemInspector(item: selectedItem)
                        .frame(maxHeight: .infinity)
                    CleanupEligibilityNote(item: selectedItem, cleanup: model.cleanup)
                    Divider()
                    CleanupPanel(cleanup: model.cleanup, cleanUp: model.cleanUp(permanently:))
                }
                .inspectorColumnWidth(min: 260, ideal: 260, max: 440)
            }
            .onChange(of: mode) {
                selection = selection.flatMap { model.result?.equivalentID(of: $0, in: mode) }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(StorageViewMode.allCases, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.result == nil)
                }
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
            .sheet(isPresented: .constant(model.isCleaningUp)) {
                CleaningUpView()
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
        case let .scanning(progress):
            ScanProgressView(progress: progress)
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
                    items: mode == .categories ? result.categories : result.locations,
                    mode: mode,
                    totalUsed: result.capacity?.used ?? result.categories.reduce(0) { $0 + $1.size },
                    selection: $selection,
                    cleanup: model.cleanup
                )
            }
        }
    }
}

/// Shown modally so nothing, including the Clean Up list, can change while items are being removed.
private struct CleaningUpView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cleaning up…").font(.headline)
            Text("Finder may ask for your password to move some items.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 300)
        .interactiveDismissDisabled()
    }
}

private struct ScanProgressView: View {
    private static let remainingFormat = Duration.UnitsFormatStyle(allowedUnits: [.minutes, .seconds], width: .wide)

    let progress: ScanModel.Progress

    var body: some View {
        TimelineView(.periodic(from: progress.started, by: 0.25)) { timeline in
            VStack(spacing: 12) {
                if let fraction = progress.fractionComplete {
                    ProgressView(value: fraction) {
                        Text("Scanning…").font(.headline)
                    } currentValueLabel: {
                        HStack {
                            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            Spacer()
                            if let remaining = progress.estimatedTimeRemaining(at: timeline.date) {
                                Text("About \(remaining.formatted(Self.remainingFormat)) left")
                            }
                        }
                        .monospacedDigit()
                    }
                    .frame(width: 320)
                } else {
                    ProgressView()
                    Text("Scanning…").font(.headline)
                }
                HStack(spacing: 12) {
                    Text("\(progress.itemCount.formatted()) items")
                    Text(progress.started, style: .timer)
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                openURL(PrivacySettings.fullDiskAccess.url)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
    }
}
