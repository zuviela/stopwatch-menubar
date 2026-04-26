import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stopwatch = StopwatchTimer()
    private let historyStore = HistoryStore()
    private lazy var historyWindowController = HistoryWindowController(store: historyStore)
    private lazy var targetsWindowController = TargetsWindowController()
    private let fireworkController = FireworkWindowController()
    private let idleMonitor = IdleMonitor(threshold: 600, pollInterval: 30)
    private var refreshTimer: Timer?
    private var pendingToggle: DispatchWorkItem?
    private var idleAlertShown = false
    private var periodAchievedToday: [Period: Bool] = [:]
    private var dailyAchievedToday: Bool = false
    private var achievementCheckDayKey: String = ""

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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

        seedAchievementState()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.fireFirework(style: .grand)
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
            checkForAchievement()
        }
        refreshLabel()
    }

    private func seedAchievementState() {
        let today = Date()
        achievementCheckDayKey = Self.dayKeyFormatter.string(from: today)
        for period in Period.allCases {
            let target = Preferences.shared.targetMinutes(for: period) * 60
            let elapsed = historyStore.seconds(forPeriod: period, on: today)
            periodAchievedToday[period] = target > 0 && elapsed >= target
        }
        let dailyTarget = Preferences.shared.dailyTargetMinutes * 60
        let dailyElapsed = historyStore.seconds(forDay: today)
        dailyAchievedToday = dailyTarget > 0 && dailyElapsed >= dailyTarget
    }

    private func checkForAchievement() {
        let today = Date()
        let dayKey = Self.dayKeyFormatter.string(from: today)
        if dayKey != achievementCheckDayKey {
            achievementCheckDayKey = dayKey
            periodAchievedToday = [:]
            dailyAchievedToday = false
        }

        let period = Period.current(at: today)
        let periodTarget = Preferences.shared.targetMinutes(for: period) * 60
        if periodTarget > 0 {
            let elapsed = historyStore.seconds(forPeriod: period, on: today)
            if !(periodAchievedToday[period] ?? false) && elapsed >= periodTarget {
                periodAchievedToday[period] = true
                fireFirework(style: .small)
            }
        }

        let dailyTarget = Preferences.shared.dailyTargetMinutes * 60
        if dailyTarget > 0 && !dailyAchievedToday {
            let elapsedDay = historyStore.seconds(forDay: today)
            if elapsedDay >= dailyTarget {
                dailyAchievedToday = true
                fireFirework(style: .grand)
            }
        }
    }

    private func fireFirework(style: FireworkStyle) {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.bounds)
        fireworkController.play(style: style, near: anchor)
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
            self.playToggleSound()
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
        playToggleSound()
        refreshLabel()
    }

    private func playToggleSound() {
        NSSound(named: "Glass")?.play()
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

        menu.addItem(buildTestFireworksItem())

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Stopwatch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        return menu
    }

    private func buildTestFireworksItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Test Fireworks", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Test Fireworks")
        submenu.autoenablesItems = false

        let small = NSMenuItem(title: "Period (small)", action: #selector(testFireworkSmall), keyEquivalent: "")
        small.target = self
        submenu.addItem(small)

        let grand = NSMenuItem(title: "Daily Goal (big)", action: #selector(testFireworkGrand), keyEquivalent: "")
        grand.target = self
        submenu.addItem(grand)

        item.submenu = submenu
        return item
    }

    @objc private func testFireworkSmall() { fireFirework(style: .small) }
    @objc private func testFireworkGrand() { fireFirework(style: .grand) }

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

        let dailyMin = Preferences.shared.dailyTargetMinutes
        let dailyElapsed = historyStore.seconds(forDay: today)
        let dailyTitle: String
        if dailyMin == 0 {
            dailyTitle = "Daily Total:  \(formatDurationCompact(dailyElapsed))  /  not set"
        } else {
            let dailySec = dailyMin * 60
            let mark = dailyElapsed >= dailySec ? "✓" : "✗"
            dailyTitle = "Daily Total:  \(formatDurationCompact(dailyElapsed))  /  \(formatDurationCompact(dailySec))  \(mark)"
        }
        let dailyItem = NSMenuItem(title: dailyTitle, action: nil, keyEquivalent: "")
        dailyItem.isEnabled = false
        submenu.addItem(dailyItem)

        submenu.addItem(NSMenuItem.separator())

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
