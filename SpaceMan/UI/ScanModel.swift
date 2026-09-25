import Foundation
import Observation

@Observable
final class ScanModel {
    enum Phase {
        case idle
        case scanning(itemCount: Int, started: Date)
        case finished(ScanResult)
    }

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
        phase = .scanning(itemCount: 0, started: started)

        scanTask = Task {
            let progress = Task {
                while !Task.isCancelled {
                    phase = .scanning(itemCount: stats.itemsScanned, started: started)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            let result = await Task.detached { await SpaceAnalyser.analyse(stats: stats) }.value
            progress.cancel()
            guard !Task.isCancelled else { return }
            phase = .finished(result)
        }
    }
}
