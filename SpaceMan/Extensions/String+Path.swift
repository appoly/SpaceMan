import Foundation

nonisolated extension String {
    func appendingPathComponent(_ component: String) -> String {
        hasSuffix("/") ? self + component : self + "/" + component
    }

    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }

    var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }

    var abbreviatingWithTilde: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
