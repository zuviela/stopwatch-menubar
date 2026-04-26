import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stopwatch = StopwatchTimer()
    private let historyStore = HistoryStore()
    private lazy var historyWindowController = HistoryWindowController(store: historyStore)
    private lazy var targetsWindowController = TargetsWindowController()
    private let idleMonitor = IdleMonitor(threshold: 600, pollInterval: 30)
    private var refreshTimer: Timer?
    private var pendingToggle: DispatchWorkItem?
    private var idleAlertShown = false

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

        idleMonitor.onIdle = { [weak self] idle in
            self?.handleIdle(seconds: idle)
        }
        idleMonitor.start()

        GlobalHotkey.shared.register(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.toggleFromHotkey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        historyStore.flush()
        idleMonitor.stop()
        GlobalHotkey.shared.unregister()
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

    private func toggleFromHotkey() {
        pendingToggle?.cancel()
        pendingToggle = nil
        stopwatch.toggle()
        refreshLabel()
    }

    private func handleIdle(seconds idleSeconds: TimeInterval) {
        guard !idleAlertShown, stopwatch.isRunning else { return }

        let idleSecs = Int(idleSeconds)
        idleAlertShown = true

        stopwatch.toggle()
        refreshLabel()

        let alert = NSAlert()
        alert.messageText = "Stopwatch paused"
        alert.informativeText = "No input detected for ~\(idleSecs / 60) min. Keep that time, or discard it?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Discard")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertSecondButtonReturn {
            stopwatch.subtractElapsed(idleSecs)
            let now = Date()
            for i in 0..<idleSecs {
                historyStore.subtractSecond(at: now.addingTimeInterval(-Double(i)))
            }
            refreshLabel()
        }

        idleAlertShown = false
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

        menu.addItem(buildDisplaySubmenuItem())
        menu.addItem(buildTargetsSubmenuItem())

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

    private func buildDisplaySubmenuItem() -> NSMenuItem {
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
        return displayItem
    }

    private func buildTargetsSubmenuItem() -> NSMenuItem {
        let targetsItem = NSMenuItem(title: "Targets", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Targets")
        submenu.autoenablesItems = false
        let today = Date()
        for period in Period.allCases {
            let elapsed = historyStore.seconds(forPeriod: period, on: today)
            let targetMin = Preferences.shared.targetMinutes(for: period)
            let targetSec = targetMin * 60
            let title: String
            if targetMin == 0 {
                title = "\(period.label):  \(formatDurationCompact(elapsed))  /  not set"
            } else {
                let mark = elapsed >= targetSec ? "✓" : "✗"
                title = "\(period.label):  \(formatDurationCompact(elapsed))  /  \(formatDurationCompact(targetSec))  \(mark)"
            }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }
        submenu.addItem(NSMenuItem.separator())
        let setItem = NSMenuItem(
            title: "Set Targets…",
            action: #selector(showTargets),
            keyEquivalent: ""
        )
        setItem.target = self
        submenu.addItem(setItem)
        targetsItem.submenu = submenu
        return targetsItem
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

    @objc private func showTargets() {
        targetsWindowController.show()
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
