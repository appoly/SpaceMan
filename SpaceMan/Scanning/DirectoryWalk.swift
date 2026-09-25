import Foundation
import Synchronization

/// A directory whose size is final once every subdirectory has reported back.
nonisolated private final class PendingDirectory: Sendable {
    struct State {
        var size: Int64 = 0
        var children: [FSNode] = []
        var remainingSubdirectories = 0
    }

    let name: String
    let path: String
    let parent: PendingDirectory?
    let state = Mutex(State())

    init(name: String, path: String, parent: PendingDirectory?) {
        self.name = name
        self.path = path
        self.parent = parent
    }
}

/// Lists directories on dedicated threads, so blocking file-system calls never occupy Swift's cooperative pool and
/// more of them can be in flight than there are cores.
nonisolated final class DirectoryWalk: @unchecked Sendable {
    typealias Lister = @Sendable (String) -> DirectoryListing?

    private let lister: Lister
    private let retainThreshold: Int64
    private let threadCount: Int
    // Guards `pending`, `isFinished` and `result`; its wait/broadcast parks idle workers.
    private let condition = NSCondition()
    private var pending: [PendingDirectory] = []
    private var isFinished = false
    private var result: FSNode?

    init(threadCount: Int, retainThreshold: Int64, lister: @escaping Lister) {
        self.threadCount = threadCount
        self.retainThreshold = retainThreshold
        self.lister = lister
    }

    func run(path: String) async -> FSNode {
        let root = PendingDirectory(name: path, path: path, parent: nil)
        pending = [root]
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let group = DispatchGroup()
                for index in 0..<threadCount {
                    group.enter()
                    let thread = Thread { [self] in
                        work()
                        group.leave()
                    }
                    thread.name = "SpaceMan scan \(index)"
                    thread.start()
                }
                group.notify(queue: .global()) { [self] in
                    let empty = FSNode(name: path, isDirectory: true, size: 0, children: [])
                    continuation.resume(returning: result ?? empty)
                }
            }
        } onCancel: {
            finish(with: nil)
        }
    }

    private func work() {
        while let directory = nextDirectory() {
            process(directory)
        }
    }

    private func nextDirectory() -> PendingDirectory? {
        condition.lock()
        defer { condition.unlock() }
        while pending.isEmpty, !isFinished {
            condition.wait()
        }
        return isFinished ? nil : pending.removeLast()
    }

    private func process(_ directory: PendingDirectory) {
        guard let listing = lister(directory.path) else {
            complete(directory)
            return
        }

        let subdirectories = listing.subdirectories.map {
            PendingDirectory(name: $0, path: directory.path.appendingPathComponent($0), parent: directory)
        }
        directory.state.withLock { state in
            state.size = listing.fileBytes
            state.children = listing.largeFiles
            state.remainingSubdirectories = subdirectories.count
        }
        guard !subdirectories.isEmpty else {
            complete(directory)
            return
        }

        condition.lock()
        pending.append(contentsOf: subdirectories)
        condition.broadcast()
        condition.unlock()
    }

    /// Folds a finished directory into its parent, walking up while each parent in turn becomes finished.
    private func complete(_ directory: PendingDirectory) {
        var current = directory
        while true {
            let node = current.state.withLock { state in
                FSNode(name: current.name, isDirectory: true, size: state.size, children: state.children)
            }
            guard let parent = current.parent else {
                finish(with: node)
                return
            }
            let parentIsComplete = parent.state.withLock { state in
                state.size += node.size
                if node.size >= retainThreshold {
                    state.children.append(node)
                }
                state.remainingSubdirectories -= 1
                return state.remainingSubdirectories == 0
            }
            guard parentIsComplete else { return }
            current = parent
        }
    }

    private func finish(with root: FSNode?) {
        condition.lock()
        defer { condition.unlock() }
        guard !isFinished else { return }
        result = root
        isFinished = true
        pending.removeAll()
        condition.broadcast()
    }
}
