import AppKit
import CoreGraphics
import IOKit.pwr_mgt

final class IdleMonitor {
    var threshold: TimeInterval {
        didSet { applyThresholdChange() }
    }
    var onIdle: (() -> Void)?
    var onReturn: (() -> Void)?

    private var timer: Timer?
    private var mode: Mode = .watchForIdle
    private let idlePollInterval: TimeInterval = 30
    private let returnPollInterval: TimeInterval = 2

    enum Mode { case watchForIdle, watchForReturn }

    private static let displayKeepAwakeTypes: Set<String> = [
        "PreventUserIdleDisplaySleep",
        "NoDisplaySleepAssertion"
    ]

    init(threshold: TimeInterval = 300) {
        self.threshold = threshold
    }

    func start() {
        switchTo(.watchForIdle)
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

    private func switchTo(_ newMode: Mode) {
        timer?.invalidate()
        mode = newMode
        let interval = (newMode == .watchForIdle) ? idlePollInterval : returnPollInterval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        switch mode {
        case .watchForIdle: checkIdle()
        case .watchForReturn: checkReturn()
        }
    }

    private func checkIdle() {
        guard threshold > 0 else { return }
        let idle = Self.currentIdleSeconds()
        guard idle >= threshold else { return }
        if Self.isDisplayKeptAwakeByOtherApp() { return }
        onIdle?()
        switchTo(.watchForReturn)
    }

    private func checkReturn() {
        let idle = Self.currentIdleSeconds()
        guard idle < 3 else { return }
        onReturn?()
        switchTo(.watchForIdle)
    }

    private func applyThresholdChange() {
        if threshold == 0, mode == .watchForReturn {
            switchTo(.watchForIdle)
        }
    }
}
