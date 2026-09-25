import Darwin
import Foundation
import Synchronization

nonisolated struct DiskCapacity: Sendable {
    let total: Int64
    let available: Int64
    let availableIncludingPurgeable: Int64

    var used: Int64 { total - available }

    static func current() -> DiskCapacity? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? URL(filePath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity
        else { return nil }
        return DiskCapacity(
            total: Int64(total),
            available: Int64(available),
            availableIncludingPurgeable: values.volumeAvailableCapacityForImportantUsage ?? Int64(available)
        )
    }
}

nonisolated struct ScanResult: Sendable {
    let categories: [StorageItem]
    let capacity: DiskCapacity?
    let scannedItemCount: Int
    let deniedFolderCount: Int
    let duration: Duration
}

nonisolated enum SpaceAnalyser {
    static let dataVolume = "/System/Volumes/Data"
    private static let retainThreshold: Int64 = 20_000_000

    static func analyse(stats: ScanStats) async -> ScanResult {
        let start = ContinuousClock.now
        async let context = NamingContext.current()
        async let tree = FileSystemScanner(retainThreshold: retainThreshold, stats: stats).scan(path: dataVolume)
        let root = await tree
        let namingContext = await context

        var extras: [StorageCategory: [ExtraItem]] = [:]
        let unreadableRuntimes = unreadableSimulatorRuntimes(in: root, context: namingContext)
        extras[.appleDevelopment] = unreadableRuntimes.map { ExtraItem(group: "Simulator runtimes", item: $0) }

        let deniedPaths = stats.deniedPaths.withLock(\.self).sorted()
        let scannedSize = root.size + unreadableRuntimes.reduce(0) { $0 + $1.size }
        let hidden = hiddenSpace(scanned: scannedSize, deniedPaths: deniedPaths)
        extras[.macOS] = systemVolumes() + [hidden].compactMap(\.self).map { ExtraItem(group: nil, item: $0) }

        let categories = Classifier(
            root: root, rules: Catalogue.rules, context: namingContext, minimumSize: retainThreshold
        ).classify(extras: extras)
        return ScanResult(
            categories: categories,
            capacity: DiskCapacity.current(),
            scannedItemCount: stats.itemsScanned,
            deniedFolderCount: deniedPaths.count,
            duration: ContinuousClock.now - start
        )
    }

    /// Files and folders on the data volume, from its inode usage.
    static var dataVolumeItemCount: Int? {
        var info = statfs()
        guard statfs(dataVolume, &info) == 0, info.f_files > info.f_ffree else { return nil }
        return Int(info.f_files - info.f_ffree)
    }

    static var hasFullDiskAccess: Bool {
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    // MARK: - Space the scan can't see

    /// Runtimes `simctl` reports whose disk images live in root-only folders.
    private static func unreadableSimulatorRuntimes(in root: FSNode, context: NamingContext) -> [StorageItem] {
        (context.simulatorRuntimes ?? []).compactMap { runtime in
            guard let path = runtime.path, let size = runtime.sizeBytes, size > 0 else { return nil }
            let scannedSize = root.node(at: path)?.size ?? 0
            guard scannedSize < size / 2 else { return nil }
            return StorageItem(
                id: "simctl:\(path)",
                title: runtime.title,
                subtitle: runtime.lastUsed,
                path: path,
                size: size,
                category: .appleDevelopment,
                about: "A simulator OS image installed from a disk image. Manage with `xcrun simctl runtime`.",
                flags: ["Size reported by simctl; SpaceMan can't read this folder"]
            )
        }
    }

    private struct SystemVolume {
        let path: String
        let title: String
        let about: String
    }

    private static func systemVolumes() -> [ExtraItem] {
        let volumes: [SystemVolume] = [
            SystemVolume(
                path: "/", title: "macOS system volume",
                about: "The sealed, read-only macOS system. Its size is set by the macOS version."
            ),
            SystemVolume(
                path: "/System/Volumes/Preboot", title: "Preboot volume",
                about: "Boot support files and staged OS updates. Managed by macOS."
            ),
            SystemVolume(
                path: "/System/Volumes/VM", title: "Swap volume",
                about: "Virtual memory swap. Grows under memory pressure and shrinks after a restart."
            )
        ]
        return volumes.compactMap { volume in
            guard let used = usedBytes(onVolumeAt: volume.path), used > 0 else { return nil }
            let item = StorageItem(
                id: "volume:\(volume.path)", title: volume.title, path: volume.path, size: used,
                category: .macOS, about: volume.about
            )
            return ExtraItem(group: "System volumes", item: item)
        }
    }

    private static func hiddenSpace(scanned: Int64, deniedPaths: [String]) -> StorageItem? {
        guard let dataUsed = usedBytes(onVolumeAt: dataVolume) else { return nil }
        let hidden = dataUsed - scanned
        guard hidden > 0 else { return nil }
        let deniedFlags = deniedPaths.isEmpty || hasFullDiskAccess
            ? []
            : ["\(deniedPaths.count) folders couldn't be read. Granting Full Disk Access reveals most of them."]
        return StorageItem(
            id: "hidden",
            title: "Hidden from scan",
            size: hidden,
            category: .macOS,
            about: "Space used on the data volume that no folder accounts for: APFS snapshots, purgeable data, " +
                "and folders only macOS itself can read.",
            flags: deniedFlags,
            unreadablePaths: deniedPaths
        )
    }

    /// `statfs` reports container-wide figures on APFS; `ATTR_VOL_SPACEUSED` is the volume's own usage.
    private static func usedBytes(onVolumeAt path: String) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)
        var buffer = [UInt8](repeating: 0, count: 32)
        guard getattrlist(path, &request, &buffer, buffer.count, 0) == 0 else { return nil }
        return buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: MemoryLayout<UInt32>.size, as: Int64.self) }
    }
}

extension FSNode {
    nonisolated func node(at path: String) -> FSNode? {
        path.split(separator: "/").reduce(Optional(self)) { node, component in
            node?.children.first { $0.name == component }
        }
    }
}
