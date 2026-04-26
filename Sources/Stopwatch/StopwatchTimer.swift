import Foundation

final class StopwatchTimer {
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    var isRunning: Bool { runningSince != nil }

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
        accumulated = 0
        runningSince = nil
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
