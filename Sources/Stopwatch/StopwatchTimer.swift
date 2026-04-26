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

    func formattedHHMM() -> String {
        let total = elapsedSeconds
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
