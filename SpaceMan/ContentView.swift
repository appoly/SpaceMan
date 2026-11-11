import AppKit
import SwiftUI

struct ContentView: View {
    @State private var model = ScanModel()
    @State private var selection: StorageItem.ID?
    @State private var showsInspector = true
    @AppStorage("viewMode") private var mode = StorageViewMode.categories
    @AppStorage("presentation") private var presentation = StoragePresentation.list
    @State private var chart = ChartState()

    var body: some View {
        let scene = chartScene
        let inspection = inspection(in: scene)
        content(scene: scene, inspected: inspection.subject?.item)
            .frame(minWidth: 760, minHeight: 480)
            .inspector(isPresented: $showsInspector) {
                VStack(spacing: 0) {
                    ItemInspector(
                        subject: inspection.subject,
                        contents: inspection.contents,
                        highlightedRowID: $chart.highlightedRowID,
                        open: inspection.open
                    )
                    .frame(maxHeight: .infinity)
                    CleanupEligibilityNote(item: inspection.subject?.item, cleanup: model.cleanup)
                    Divider()
                    CleanupPanel(cleanup: model.cleanup, cleanUp: model.cleanUp(permanently:))
                }
                .inspectorColumnWidth(min: 260, ideal: 260, max: 440)
            }
            .onChange(of: mode) {
                selection = selection.flatMap { model.result?.equivalentID(of: $0, in: mode) }
                chart.focusPath = []
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
                ToolbarSpacer(.fixed, placement: .principal)
                ToolbarItem(placement: .principal) {
                    Picker("Presentation", selection: $presentation) {
                        ForEach(StoragePresentation.allCases, id: \.self) { presentation in
                            Label(presentation.title, systemImage: presentation.symbol)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.result == nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(model.result == nil ? "Scan" : "Rescan", systemImage: "arrow.clockwise") {
                        model.scan()
                    }
                    .disabled(model.isScanning || (!model.hasFullDiskAccess && model.result == nil))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Inspector", systemImage: "sidebar.right") {
                        withAnimation { showsInspector.toggle() }
                    }
                }
            }
            .sheet(isPresented: .constant(model.isCleaningUp)) {
                CleaningUpView()
            }
            .task { model.scanIfReady() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.scanIfReady()
            }
    }

    private var selectedItem: StorageItem? {
        selection.flatMap { model.result?.allItems.item(withID: $0) }
    }

    private var chartScene: ChartScene? {
        guard let result = model.result else { return nil }
        switch presentation {
        case .list:
            return nil
        case .chart:
            return ChartScene(
                items: items(in: result), capacity: result.capacity, palette: mode.chartPalette,
                focusPath: chart.focusPath
            )
        }
    }

    /// The chart's inspector follows the pointer, falling back to the selection, then the level shown.
    private func inspection(in scene: ChartScene?) -> Inspection {
        guard let scene else {
            return Inspection(
                subject: selectedItem.map(InspectorSubject.item),
                contents: (selectedItem?.children ?? []).sortedBySize.map { ContentsRow(item: $0) },
                open: nil
            )
        }
        if let hovered = chart.hovered {
            return switch hovered.content {
            case let .item(item):
                Inspection(subject: .item(item), contents: scene.rows(for: item.children ?? []), open: nil)
            case .unlisted, .freeSpace:
                Inspection(
                    subject: .summary(title: hovered.content.title, size: hovered.content.size), contents: [], open: nil
                )
            }
        }
        let open = { (item: StorageItem) in self.open(item, in: scene) }
        if let item = selectedItem ?? scene.trail.last {
            return Inspection(subject: .item(item), contents: scene.rows(for: item.children ?? []), open: open)
        }
        return Inspection(
            subject: .summary(title: scene.rootTitle, size: scene.rootSize),
            contents: scene.rows(for: scene.items) + scene.extraRows,
            open: open
        )
    }

    /// Selects the item and, if it has anything inside, makes it the chart's centre.
    private func open(_ item: StorageItem, in scene: ChartScene) {
        selection = item.id
        guard item.children != nil, let lineage = scene.items.lineage(to: item.id) else { return }
        chart.hovered = nil
        chart.highlightedRowID = nil
        withAnimation {
            chart.focusPath = lineage
        }
    }

    private func navigate(toDepth depth: Int, in scene: ChartScene) {
        let kept = scene.trail.prefix(depth)
        selection = kept.last?.id
        chart.hovered = nil
        withAnimation {
            chart.focusPath = kept.map(\.id)
        }
    }

    private func items(in result: ScanResult) -> [StorageItem] {
        switch mode {
        case .categories: result.categories
        case .folders: result.locations
        }
    }

    @ViewBuilder
    private func content(scene: ChartScene?, inspected: StorageItem?) -> some View {
        switch model.phase {
        case .idle:
            if model.hasFullDiskAccess {
                ContentUnavailableView("Ready to Scan", systemImage: "internaldrive")
            } else {
                FullDiskAccessSetupView(scanWithoutAccess: model.scan)
            }
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

                if let scene {
                    Divider()
                    ChartBrowser(
                        scene: scene,
                        state: chart,
                        selection: selection,
                        open: { open($0, in: scene) },
                        navigate: { navigate(toDepth: $0, in: scene) }
                    )
                } else {
                    StorageTable(
                        items: items(in: result),
                        mode: mode,
                        totalUsed: result.capacity?.used ?? result.categories.reduce(0) { $0 + $1.size },
                        selection: $selection,
                        cleanup: model.cleanup
                    )
                }

                if !showsInspector {
                    Divider()
                    DetailsStrip(item: inspected, cleanup: model.cleanup, cleanUp: model.cleanUp(permanently:)) {
                        withAnimation { showsInspector = true }
                    }
                }
            }
        }
    }
}

private struct Inspection {
    let subject: InspectorSubject?
    let contents: [ContentsRow]
    let open: ((StorageItem) -> Void)?
}

/// Shown modally so nothing, including the Clean Up list, can change while items are being removed.
private struct CleaningUpView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cleaning up…").font(.headline)
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
