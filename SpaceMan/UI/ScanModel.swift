import Foundation
import Observation

@Observable
final class ScanModel {
    /// Read live by a main-thread timeline: the scan saturates the cooperative pool, so an async polling loop there
    /// wouldn't get scheduled until it finished.
    struct Progress {
        let stats: ScanStats
        let started: Date
        let expectedItemCount: Int?

        var itemCount: Int {
            stats.itemsScanned
        }

        var fractionComplete: Double? {
            expectedItemCount.map { min(0.99, Double(itemCount) / Double($0)) }
        }

        func estimatedTimeRemaining(at date: Date) -> Duration? {
            let elapsed = date.timeIntervalSince(started)
            guard let fraction = fractionComplete, fraction >= 0.05, elapsed >= 2 else { return nil }
            return .seconds(elapsed * (1 - fraction) / fraction)
        }
    }

    enum Phase {
        case idle
        case scanning(Progress)
        case finished(ScanResult)
    }

    private static let lastScannedItemCountKey = "lastScannedItemCount"

    private(set) var phase = Phase.idle
    /// Covers deleting and recalculating; the UI is blocked throughout.
    private(set) var isCleaningUp = false
    let cleanup = CleanupList()
    private(set) var hasFullDiskAccess = SpaceAnalyser.hasFullDiskAccess
    private var scanTask: Task<Void, Never>?

    var result: ScanResult? {
        guard case let .finished(result) = phase else { return nil }
        return result
    }

    var isScanning: Bool {
        guard case .scanning = phase else { return false }
        return true
    }

    /// Scans on first launch, or once Full Disk Access turns up, but never without it unless asked to.
    func scanIfReady() {
        hasFullDiskAccess = SpaceAnalyser.hasFullDiskAccess
        guard hasFullDiskAccess, case .idle = phase else { return }
        scan()
    }

    /// Without Full Disk Access, folders macOS would ask about are skipped and reported as unreadable.
    func scan() {
        scanTask?.cancel()
        hasFullDiskAccess = SpaceAnalyser.hasFullDiskAccess
        let skipsPromptingFolders = !hasFullDiskAccess
        let stats = ScanStats()
        phase = .scanning(Progress(stats: stats, started: Date(), expectedItemCount: expectedItemCount()))

        scanTask = Task {
            let result = await Task.detached {
                await SpaceAnalyser.analyse(stats: stats, skipsPromptingFolders: skipsPromptingFolders)
            }.value
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(result.scannedItemCount, forKey: Self.lastScannedItemCountKey)
            cleanup.update(index: result.cleanupIndex)
            phase = .finished(result)
        }
    }

    /// Updates every figure from what was removed rather than rescanning the disk.
    func cleanUp(permanently: Bool) async -> [CleanupFailure] {
        isCleaningUp = true
        defer { isCleaningUp = false }
        let outcome = await cleanup.cleanUp(permanently: permanently)
        guard let result else { return outcome.failures }
        let updated = await Task.detached { await SpaceAnalyser.applying(outcome, to: result) }.value
        cleanup.update(index: updated.cleanupIndex)
        phase = .finished(updated)
        return outcome.failures
    }

    /// Scan time tracks items visited rather than bytes, which a few huge files dominate. The previous scan's count
    /// excludes unreadable folders, so it beats the volume's inode count once available.
    private func expectedItemCount() -> Int? {
        let lastScanned = UserDefaults.standard.integer(forKey: Self.lastScannedItemCountKey)
        return lastScanned > 0 ? lastScanned : SpaceAnalyser.dataVolumeItemCount
    }
}

extension ScanResult {
    var allItems: [StorageItem] {
        categories + locations
    }

    /// The same path's row in the other view, so switching views keeps the selection where possible.
    func equivalentID(of id: StorageItem.ID, in mode: StorageViewMode) -> StorageItem.ID? {
        guard let path = allItems.item(withID: id)?.path else { return nil }
        let target = switch mode {
        case .categories: categories
        case .folders: locations
        }
        return target.item(withPath: path)?.id
    }
}
