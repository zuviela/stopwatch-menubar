import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stopwatch = StopwatchTimer()
    private let historyStore = HistoryStore()
    private lazy var historyWindowController = HistoryWindowController(store: historyStore)
    private lazy var targetsWindowController = TargetsWindowController()
    private let fireworkController = FireworkWindowController()
    private let idleMonitor = IdleMonitor()
    private let returnPromptController = ReturnPromptController()
    private var refreshTimer: Timer?
    private var pendingToggle: DispatchWorkItem?
    private var idlePauseTimestamp: Date?
    private var periodAchievedToday: [Period: Bool] = [:]
    private var dailyAchievedToday: Bool = false
    private var achievementCheckDayKey: String = ""
    private var allowTermination: Bool = false
    private var scrollMonitor: Any?
    private var scrollAccumulator: Double = 0
    private var lastScrollAt: Date?
    private static let scrollThresholdTrackpad: Double = 40
    private static let scrollThresholdMouse: Double = 10
    private static let scrollIdleReset: TimeInterval = 0.5
    private static let scrollAdjustSeconds: Int = 10

    private static let idleThresholdOptions: [(label: String, seconds: Int)] = [
        ("Disabled", 0),
        ("1 minute", 60),
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600)
    ]


    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        refreshLabel()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }

        idleMonitor.threshold = TimeInterval(Preferences.shared.idleThresholdSeconds)
        idleMonitor.onIdle = { [weak self] in self?.handleIdleDetected() }
        idleMonitor.onReturn = { [weak self] in self?.handleUserReturned() }
        idleMonitor.start()

        GlobalHotkey.shared.register(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.toggleFromHotkey()
        }

        seedAchievementState()
        installScrollMonitor()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.fireFirework(style: .grand)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopwatch.saveState()
        historyStore.flush()
        idleMonitor.stop()
        GlobalHotkey.shared.unregister()
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self else { return event }
            guard let button = self.statusItem.button, event.window === button.window else { return event }
            guard event.modifierFlags.contains(.command) else { return event }
            guard !self.stopwatch.isRunning else { return event }

            let delta = event.scrollingDeltaY
            if delta == 0 { return nil }

            let threshold = event.hasPreciseScrollingDeltas
                ? Self.scrollThresholdTrackpad
                : Self.scrollThresholdMouse

            let now = Date()
            if let last = self.lastScrollAt, now.timeIntervalSince(last) > Self.scrollIdleReset {
                self.scrollAccumulator = 0
            }
            self.lastScrollAt = now
            self.scrollAccumulator += delta

            var changed = false
            while self.scrollAccumulator >= threshold {
                self.stopwatch.addElapsed(Self.scrollAdjustSeconds)
                self.scrollAccumulator -= threshold
                changed = true
            }
            while self.scrollAccumulator <= -threshold {
                self.stopwatch.subtractElapsed(Self.scrollAdjustSeconds)
                self.scrollAccumulator += threshold
                changed = true
            }
            if changed { self.refreshLabel() }
            return nil
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return allowTermination ? .terminateNow : .terminateCancel
    }

    @objc private func quitFromMenu() {
        allowTermination = true
        NSApp.terminate(nil)
    }

    private func tick() {
        if stopwatch.isRunning {
            historyStore.recordSecond(at: Date())
            checkForAchievement()
            stopwatch.saveState()
        }
        refreshLabel()
    }

    private func seedAchievementState() {
        let today = Date()
        achievementCheckDayKey = HistoryStore.dayKey(for: today)
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
        let dayKey = HistoryStore.dayKey(for: today)
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
            cancelPendingIdleReturn()
            stopwatch.reset()
            refreshLabel()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cancelPendingIdleReturn()
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

    private func cancelPendingIdleReturn() {
        if idlePauseTimestamp != nil {
            idlePauseTimestamp = nil
            returnPromptController.close()
        }
    }

    private func toggleFromHotkey() {
        pendingToggle?.cancel()
        pendingToggle = nil
        cancelPendingIdleReturn()
        stopwatch.toggle()
        playToggleSound()
        refreshLabel()
    }

    private func playToggleSound() {
        NSSound(named: "Glass")?.play()
    }

    private func handleIdleDetected() {
        guard stopwatch.isRunning else { return }
        idlePauseTimestamp = Date()
        stopwatch.toggle()
        refreshLabel()
    }

    private func handleUserReturned() {
        guard let pauseTime = idlePauseTimestamp else { return }
        let extraAway = Int(Date().timeIntervalSince(pauseTime))
        idlePauseTimestamp = nil
        guard extraAway > 0, let button = statusItem.button else { return }

        returnPromptController.show(
            extraAwaySeconds: extraAway,
            relativeTo: button
        ) { [weak self] keep in
            guard let self else { return }
            if keep {
                self.stopwatch.addElapsed(extraAway)
                for i in 0..<extraAway {
                    self.historyStore.recordSecond(at: pauseTime.addingTimeInterval(Double(i)))
                }
                if !self.stopwatch.isRunning {
                    self.stopwatch.toggle()
                    self.playToggleSound()
                }
            }
            self.refreshLabel()
        }
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
        menu.addItem(buildIdleThresholdSubmenuItem())

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

        menu.addItem(buildLaunchAtLoginItem())

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Tally",
            action: #selector(quitFromMenu),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func buildLaunchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        item.target = self
        item.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        return item
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Tally: launch-at-login toggle failed: \(error)")
        }
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

    private func buildIdleThresholdSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Idle Pause After", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Idle Pause After")
        submenu.autoenablesItems = false
        let current = Preferences.shared.idleThresholdSeconds
        for (label, seconds) in Self.idleThresholdOptions {
            let menuItem = NSMenuItem(
                title: label,
                action: #selector(setIdleThreshold(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = seconds
            menuItem.state = (seconds == current) ? .on : .off
            submenu.addItem(menuItem)
        }
        item.submenu = submenu
        return item
    }

    @objc private func setIdleThreshold(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        Preferences.shared.idleThresholdSeconds = seconds
        idleMonitor.threshold = TimeInterval(seconds)
        if seconds == 0 {
            cancelPendingIdleReturn()
        }
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
        statusItem.button?.title = ""
        statusItem.button?.image = renderStatusImage(text: title)
    }

    private func renderStatusImage(text: String) -> NSImage {
        let menuBarSize = NSFont.menuBarFont(ofSize: 0).pointSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: menuBarSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let horizontalPadding: CGFloat = 7
        let verticalPadding: CGFloat = 1.5
        let cornerRadius: CGFloat = 4
        let lineWidth: CGFloat = 1

        let width = ceil(textSize.width + horizontalPadding * 2 + lineWidth)
        let height = ceil(textSize.height + verticalPadding * 2 + lineWidth)
        let imageSize = NSSize(width: width, height: height)

        let image = NSImage(size: imageSize)
        image.isTemplate = true
        image.lockFocus()

        let borderRect = NSRect(
            x: lineWidth / 2,
            y: lineWidth / 2,
            width: imageSize.width - lineWidth,
            height: imageSize.height - lineWidth
        )
        let path = NSBezierPath(
            roundedRect: borderRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        NSColor.labelColor.setStroke()
        path.lineWidth = lineWidth
        path.stroke()

        let textRect = NSRect(
            x: (imageSize.width - textSize.width) / 2,
            y: (imageSize.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: textRect)

        image.unlockFocus()
        return image
    }
}
