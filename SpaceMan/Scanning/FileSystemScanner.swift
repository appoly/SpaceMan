import Darwin
import Foundation
import Synchronization

nonisolated struct FSNode: Sendable {
    var name: String
    let isDirectory: Bool
    var size: Int64
    var children: [FSNode]
}

nonisolated final class ScanStats: Sendable {
    let itemCount = Atomic<Int>(0)
    let deniedPaths = Mutex<[String]>([])
    private let seenHardLinks = Mutex<Set<UInt64>>([])

    var itemsScanned: Int {
        itemCount.load(ordering: .relaxed)
    }

    func isFirstSighting(ofHardLink fileID: UInt64) -> Bool {
        seenHardLinks.withLock { $0.insert(fileID).inserted }
    }
}

nonisolated struct DirectoryListing: Sendable {
    var fileBytes: Int64 = 0
    var largeFiles: [FSNode] = []
    var subdirectories: [String] = []
}

/// Walks a single volume with `getattrlistbulk`, returning a tree that keeps only entries of at least
/// `retainThreshold` bytes; everything smaller is folded into its parent's size.
nonisolated struct FileSystemScanner: Sendable {
    let retainThreshold: Int64
    let stats: ScanStats
    /// Reported as unreadable without being opened.
    let skippedPaths: Set<String>
    private let threadCount: Int

    /// APFS serialises much of the metadata work in the kernel, so beyond ~¾ of the cores extra threads only add
    /// lock contention: on 8 cores, 6 threads scan as fast as 64 with 20% less CPU.
    static let defaultThreadCount = max(2, ProcessInfo.processInfo.activeProcessorCount * 3 / 4)

    init(
        retainThreshold: Int64, stats: ScanStats, skippedPaths: Set<String> = [], threadCount: Int = defaultThreadCount
    ) {
        self.retainThreshold = retainThreshold
        self.stats = stats
        self.skippedPaths = skippedPaths
        self.threadCount = threadCount
    }

    func scan(path: String) async -> FSNode {
        await DirectoryWalk(threadCount: threadCount, retainThreshold: retainThreshold) { list($0) }.run(path: path)
    }

    // MARK: - Directory listing

    private static let bufferSize = 256 * 1024

    private func list(_ path: String) -> DirectoryListing? {
        guard !skippedPaths.contains(path) else {
            stats.deniedPaths.withLock { $0.append(path) }
            return nil
        }
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == EACCES || errno == EPERM {
                stats.deniedPaths.withLock { $0.append(path) }
            }
            return nil
        }
        defer { close(descriptor) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_ERROR | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_FILEID)
        request.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
        request.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var listing = DirectoryListing()
        while true {
            let count = getattrlistbulk(descriptor, &request, buffer, Self.bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            guard count > 0 else { break }

            var entry = buffer
            for _ in 0..<count {
                let parsed = BulkEntry(entry)
                entry += Int(parsed.length)
                record(parsed, in: &listing)
            }
            stats.itemCount.add(Int(count), ordering: .relaxed)
        }
        return listing
    }

    private func record(_ entry: BulkEntry, in listing: inout DirectoryListing) {
        guard entry.error == 0 else { return }

        switch entry.objectType {
        case UInt32(VDIR.rawValue):
            if entry.mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) == 0 {
                listing.subdirectories.append(entry.name)
            }
        case UInt32(VREG.rawValue):
            if entry.linkCount > 1, !stats.isFirstSighting(ofHardLink: entry.fileID) {
                return
            }
            listing.fileBytes += entry.allocatedSize
            if entry.allocatedSize >= retainThreshold {
                listing.largeFiles.append(
                    FSNode(name: entry.name, isDirectory: false, size: entry.allocatedSize, children: [])
                )
            }
        default:
            break
        }
    }
}

/// One record from a `getattrlistbulk` buffer. `FSOPT_PACK_INVAL_ATTRS` pads the common attributes, but directory
/// records carry only directory attributes and all other records only file attributes.
nonisolated private struct BulkEntry {
    let length: UInt32
    let error: UInt32
    let name: String
    let objectType: UInt32
    let fileID: UInt64
    let mountStatus: UInt32
    let linkCount: UInt32
    let allocatedSize: Int64

    init(_ base: UnsafeMutableRawPointer) {
        var cursor = UnsafeRawPointer(base)
        length = cursor.loadUnaligned(as: UInt32.self)
        cursor += MemoryLayout<UInt32>.size
        cursor += MemoryLayout<attribute_set_t>.size

        error = cursor.loadUnaligned(as: UInt32.self)
        cursor += MemoryLayout<UInt32>.size

        let nameOffset = cursor.loadUnaligned(as: Int32.self)
        name = String(cString: (cursor + Int(nameOffset)).assumingMemoryBound(to: CChar.self))
        cursor += MemoryLayout<attrreference_t>.size

        objectType = cursor.loadUnaligned(as: UInt32.self)
        cursor += MemoryLayout<fsobj_type_t>.size

        fileID = cursor.loadUnaligned(as: UInt64.self)
        cursor += MemoryLayout<UInt64>.size

        guard objectType != UInt32(VDIR.rawValue) else {
            mountStatus = cursor.loadUnaligned(as: UInt32.self)
            linkCount = 0
            allocatedSize = 0
            return
        }
        mountStatus = 0
        linkCount = cursor.loadUnaligned(as: UInt32.self)
        cursor += MemoryLayout<UInt32>.size

        allocatedSize = cursor.loadUnaligned(as: Int64.self)
    }
}
