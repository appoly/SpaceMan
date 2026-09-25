import Foundation
import Observation

@Observable
final class ScanModel {
    struct Progress {
        let itemCount: Int
        let started: Date
        /// `nil` until there's something to estimate against.
        let fractionComplete: Double?
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
        let started = Date()
        let expectedItems = expectedItemCount()
        phase = .scanning(Progress(itemCount: 0, started: started, fractionComplete: expectedItems.map { _ in 0 }))

        scanTask = Task {
            let progress = Task {
                while !Task.isCancelled {
                    let fraction = expectedItems.map { min(0.99, Double(stats.itemsScanned) / Double($0)) }
                    phase = .scanning(
                        Progress(itemCount: stats.itemsScanned, started: started, fractionComplete: fraction)
                    )
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            let result = await Task.detached { await SpaceAnalyser.analyse(stats: stats) }.value
            progress.cancel()
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
