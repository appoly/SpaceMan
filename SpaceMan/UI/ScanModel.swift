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

    func scan() {
        scanTask?.cancel()
        hasFullDiskAccess = SpaceAnalyser.hasFullDiskAccess
        let stats = ScanStats()
        phase = .scanning(Progress(stats: stats, started: Date(), expectedItemCount: expectedItemCount()))

        scanTask = Task {
            let result = await Task.detached { await SpaceAnalyser.analyse(stats: stats) }.value
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(result.scannedItemCount, forKey: Self.lastScannedItemCountKey)
            phase = .finished(result)
        }
    }

    /// Scan time tracks items visited rather than bytes, which a few huge files dominate. The previous scan's count
    /// excludes unreadable folders, so it beats the volume's inode count once available.
    private func expectedItemCount() -> Int? {
        let lastScanned = UserDefaults.standard.integer(forKey: Self.lastScannedItemCountKey)
        return lastScanned > 0 ? lastScanned : SpaceAnalyser.dataVolumeItemCount
    }
}
