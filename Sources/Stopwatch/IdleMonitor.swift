import AppKit
import CoreGraphics

final class IdleMonitor {
    var threshold: TimeInterval
    var pollInterval: TimeInterval
    var onIdle: ((TimeInterval) -> Void)?

    private var timer: Timer?

    init(threshold: TimeInterval = 600, pollInterval: TimeInterval = 30) {
        self.threshold = threshold
        self.pollInterval = pollInterval
    }

    func start() {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func currentIdleSeconds() -> TimeInterval {
        let anyType = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyType)
    }

    private func check() {
        let idle = Self.currentIdleSeconds()
        if idle >= threshold {
            onIdle?(idle)
        }
    }
}
