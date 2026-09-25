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

extension NSWindow {
    /// Selectable SwiftUI text keeps first responder after the table is clicked, which leaves the table's selection
    /// inactive and deaf to the keyboard until the app is deactivated.
    func reclaimFocusForTable() {
        guard !(firstResponder is NSTableView),
              let table = contentView?.firstDescendant(ofType: NSTableView.self)
        else { return }
        makeFirstResponder(table)
    }
}

extension NSView {
    func firstDescendant<View: NSView>(ofType type: View.Type) -> View? {
        for subview in subviews {
            if let match = subview as? View ?? subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}
