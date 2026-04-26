import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stopwatch = StopwatchTimer()
    private let historyStore = HistoryStore()
    private lazy var historyWindowController = HistoryWindowController(store: historyStore)
    private var refreshTimer: Timer?
    private var pendingToggle: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        refreshLabel()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        historyStore.flush()
    }

    private func tick() {
        if stopwatch.isRunning {
            historyStore.recordSecond(at: Date())
        }
        refreshLabel()
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
        statusItem.menu = buildContextMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let undoItem = NSMenuItem(
            title: "Undo Reset",
            action: #selector(undoReset),
            keyEquivalent: "z"
        )
        undoItem.target = self
        undoItem.isEnabled = stopwatch.canUndoReset
        menu.addItem(undoItem)

        menu.addItem(NSMenuItem.separator())

        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let displaySubmenu = NSMenu(title: "Display")
        displaySubmenu.autoenablesItems = false
        let current = Preferences.shared.displayFormat
        for format in DisplayFormat.allCases {
            let item = NSMenuItem(
                title: format.label,
                action: #selector(setDisplayFormat(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = format.rawValue
            item.state = (format == current) ? .on : .off
            displaySubmenu.addItem(item)
        }
        displayItem.submenu = displaySubmenu
        menu.addItem(displayItem)

        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem(
            title: "Show History…",
            action: #selector(showHistory),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Stopwatch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        return menu
    }

    @objc private func undoReset() {
        stopwatch.undoReset()
        refreshLabel()
    }

    @objc private func setDisplayFormat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let format = DisplayFormat(rawValue: raw) else { return }
        Preferences.shared.displayFormat = format
        refreshLabel()
    }

    @objc private func showHistory() {
        historyWindowController.show()
    }

    private func refreshLabel() {
        let format = Preferences.shared.displayFormat
        let time = formatElapsed(stopwatch.elapsedSeconds, format: format)
        let title: String
        switch format {
        case .hm:
            title = stopwatch.isRunning ? "● \(time)" : time
        case .hms:
            title = time
        }
        statusItem.button?.title = title
    }
}
