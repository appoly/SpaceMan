import AppKit

extension NSWorkspace {
    func revealInFinder(_ path: String) {
        activateFileViewerSelecting([URL(filePath: path)])
    }
}

extension NSPasteboard {
    func copy(_ string: String) {
        clearContents()
        setString(string, forType: .string)
    }
}
