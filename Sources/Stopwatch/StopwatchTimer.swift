import Foundation

final class StopwatchTimer {
    private static let elapsedKey = "stopwatch.savedElapsedSeconds"
    private static let lastCycleKey = "stopwatch.savedLastCycleSeconds"

    private var accumulated: TimeInterval = 0
    private var runningSince: Date?
    private var lastCycleSeconds: Int?

    init() {
        loadState()
    }

    var isRunning: Bool { runningSince != nil }

    var canUndoReset: Bool { lastCycleSeconds != nil }

    var elapsedSeconds: Int {
        let live = runningSince.map { Date().timeIntervalSince($0) } ?? 0
        return Int(accumulated + live)
    }

    func toggle() {
        if let start = runningSince {
            accumulated += Date().timeIntervalSince(start)
            runningSince = nil
        } else {
            runningSince = Date()
        }
        saveState()
    }

    func reset() {
        let current = elapsedSeconds
        if current > 0 {
            lastCycleSeconds = current
        }
        accumulated = 0
        runningSince = nil
        saveState()
    }

    func undoReset() {
        guard let saved = lastCycleSeconds else { return }
        accumulated = TimeInterval(saved)
        runningSince = nil
        lastCycleSeconds = nil
        saveState()
    }

    func subtractElapsed(_ seconds: Int) {
        let s = TimeInterval(max(0, seconds))
        accumulated = max(0, accumulated - s)
        saveState()
    }

    func addElapsed(_ seconds: Int) {
        accumulated += TimeInterval(max(0, seconds))
        saveState()
    }

    func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(elapsedSeconds, forKey: Self.elapsedKey)
        if let last = lastCycleSeconds {
            defaults.set(last, forKey: Self.lastCycleKey)
        } else {
            defaults.removeObject(forKey: Self.lastCycleKey)
        }
    }

    private func loadState() {
        let defaults = UserDefaults.standard
        let saved = defaults.integer(forKey: Self.elapsedKey)
        accumulated = TimeInterval(max(0, saved))
        if defaults.object(forKey: Self.lastCycleKey) != nil {
            lastCycleSeconds = defaults.integer(forKey: Self.lastCycleKey)
        }
    }
}

func formatElapsed(_ seconds: Int, format: DisplayFormat) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    switch format {
    case .hm:
        return h > 0
            ? String(format: "%02d:%02d", h, m)
            : String(format: "%02d", m)
    case .hms:
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

func formatDurationCompact(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    if h > 0 {
        return String(format: "%dh %02dm", h, m)
    }
    return "\(m)m"
}
