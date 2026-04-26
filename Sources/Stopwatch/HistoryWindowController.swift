import AppKit
import SwiftUI

final class HistoryWindowController {
    private var window: NSWindow?
    private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: HistoryView(store: store))
            let win = NSWindow(contentViewController: host)
            win.title = "Stopwatch History"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
