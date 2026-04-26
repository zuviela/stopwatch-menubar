import Foundation

final class StopwatchTimer {
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?
    private var lastCycleSeconds: Int?

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
    }

    func reset() {
        let current = elapsedSeconds
        if current > 0 {
            lastCycleSeconds = current
        }
        accumulated = 0
        runningSince = nil
    }

    func undoReset() {
        guard let saved = lastCycleSeconds else { return }
        accumulated = TimeInterval(saved)
        runningSince = nil
        lastCycleSeconds = nil
    }

    func subtractElapsed(_ seconds: Int) {
        let s = TimeInterval(max(0, seconds))
        accumulated = max(0, accumulated - s)
    }
}

func formatElapsed(_ seconds: Int, format: DisplayFormat) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    switch format {
    case .hm:
        return String(format: "%d:%02d", h, m)
    case .hms:
        return String(format: "%d:%02d:%02d", h, m, s)
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
