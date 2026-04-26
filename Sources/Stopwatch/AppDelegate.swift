import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stopwatch = StopwatchTimer()
    private var refreshTimer: Timer?
    private var pendingToggle: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = stopwatch.formattedHHMM()
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshLabel()
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if event.clickCount >= 2 {
            pendingToggle?.cancel()
            pendingToggle = nil
            stopwatch.reset()
            refreshLabel()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stopwatch.toggle()
            self.refreshLabel()
            self.pendingToggle = nil
        }
        pendingToggle = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + NSEvent.doubleClickInterval,
            execute: work
        )
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Stopwatch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func refreshLabel() {
        statusItem.button?.title = stopwatch.formattedHHMM()
    }
}
