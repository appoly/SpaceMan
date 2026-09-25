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

    private static let lastScannedBytesKey = "lastScannedBytes"

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
        let expectedBytes = expectedScanBytes()
        phase = .scanning(Progress(itemCount: 0, started: started, fractionComplete: expectedBytes.map { _ in 0 }))

        scanTask = Task {
            let progress = Task {
                while !Task.isCancelled {
                    let fraction = expectedBytes.map { min(0.99, Double(stats.bytesScanned) / Double($0)) }
                    phase = .scanning(
                        Progress(itemCount: stats.itemsScanned, started: started, fractionComplete: fraction)
                    )
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            let result = await Task.detached { await SpaceAnalyser.analyse(stats: stats) }.value
            progress.cancel()
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(result.scannedBytes, forKey: Self.lastScannedBytesKey)
            phase = .finished(result)
        }
    }

    /// The previous scan's total is the best estimate, since the volume's usage includes space no scan can see.
    private func expectedScanBytes() -> Int64? {
        let lastScanned = Int64(UserDefaults.standard.integer(forKey: Self.lastScannedBytesKey))
        if lastScanned > 0 {
            return lastScanned
        }
        return SpaceAnalyser.dataVolumeUsedBytes.flatMap { $0 > 0 ? $0 : nil }
    }
}
