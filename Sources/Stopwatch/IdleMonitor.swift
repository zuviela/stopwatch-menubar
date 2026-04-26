import AppKit
import CoreGraphics
import IOKit.pwr_mgt

final class IdleMonitor {
    var threshold: TimeInterval
    var pollInterval: TimeInterval
    var onIdle: ((TimeInterval) -> Void)?

    private var timer: Timer?

    private static let displayKeepAwakeTypes: Set<String> = [
        "PreventUserIdleDisplaySleep",
        "NoDisplaySleepAssertion"
    ]

    init(threshold: TimeInterval = 600, pollInterval: TimeInterval = 30) {
        self.threshold = threshold
        self.pollInterval = pollInterval
    }

    func start() {
        stop()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func currentIdleSeconds() -> TimeInterval {
        let anyType = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyType)
    }

    static func isDisplayKeptAwakeByOtherApp() -> Bool {
        var pidsByAssertion: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&pidsByAssertion)
        guard result == kIOReturnSuccess,
              let dict = pidsByAssertion?.takeRetainedValue() as? [Int: [[String: Any]]] else {
            return false
        }
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        for (pid, assertions) in dict where pid != me {
            for assertion in assertions {
                if let type = assertion["AssertType"] as? String,
                   displayKeepAwakeTypes.contains(type) {
                    return true
                }
            }
        }
        return false
    }

    private func check() {
        let idle = Self.currentIdleSeconds()
        guard idle >= threshold else { return }
        if Self.isDisplayKeptAwakeByOtherApp() { return }
        onIdle?(idle)
    }
}
