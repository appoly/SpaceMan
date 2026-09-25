import AppKit
import SwiftUI

/// SwiftUI's `Table` only resizes its last column with the window. With a fixed-width column last, that means it
/// scrolls horizontally straight away; uniform resizing squashes the flexible columns first.
struct TableViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguringView {
        ConfiguringView()
    }

    func updateNSView(_ nsView: ConfiguringView, context: Context) {}

    final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.window?.contentView?.firstDescendant(ofType: NSTableView.self)?
                    .columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            }
        }
    }
}
