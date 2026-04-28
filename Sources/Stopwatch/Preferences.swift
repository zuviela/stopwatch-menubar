import Foundation

enum DisplayFormat: String, CaseIterable {
    case hm
    case hms

    var label: String {
        switch self {
        case .hm: return "H:MM"
        case .hms: return "H:MM:SS"
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let displayFormatKey = "displayFormat"

    var displayFormat: DisplayFormat {
        get {
            guard let raw = defaults.string(forKey: displayFormatKey),
                  let format = DisplayFormat(rawValue: raw) else {
                return .hm
            }
            return format
        }
        set {
            defaults.set(newValue.rawValue, forKey: displayFormatKey)
        }
    }

    func targetMinutes(for period: Period) -> Int {
        defaults.integer(forKey: targetKey(period))
    }

    func setTargetMinutes(_ minutes: Int, for period: Period) {
        defaults.set(max(0, minutes), forKey: targetKey(period))
    }

    var dailyTargetMinutes: Int {
        Period.allCases.reduce(0) { $0 + targetMinutes(for: $1) }
    }

    private let lockedGoalsKey = "lockedGoalsByDay"
    private let maxLockedDaysRetained = 60

    private func lockedGoalsRaw() -> [String: [String: Int]] {
        return (defaults.dictionary(forKey: lockedGoalsKey) as? [String: [String: Int]]) ?? [:]
    }

    func lockedGoals(for dayKey: String) -> [Period: Int]? {
        guard let dayDict = lockedGoalsRaw()[dayKey] else { return nil }
        var result: [Period: Int] = [:]
        for (raw, minutes) in dayDict {
            if let period = Period(rawValue: raw) {
                result[period] = max(0, minutes)
            }
        }
        return result
    }

    func goalsAreLocked(for dayKey: String) -> Bool {
        return lockedGoalsRaw()[dayKey] != nil
    }

    func lockGoals(_ goals: [Period: Int], for dayKey: String) {
        var dict = lockedGoalsRaw()
        var dayDict: [String: Int] = [:]
        for (period, minutes) in goals {
            dayDict[period.rawValue] = max(0, minutes)
        }
        dict[dayKey] = dayDict
        if dict.count > maxLockedDaysRetained {
            let kept = Set(dict.keys.sorted(by: >).prefix(maxLockedDaysRetained))
            dict = dict.filter { kept.contains($0.key) }
        }
        defaults.set(dict, forKey: lockedGoalsKey)
    }

    func effectiveTargetMinutes(for period: Period, on dayKey: String) -> Int {
        if let locked = lockedGoals(for: dayKey), let minutes = locked[period] {
            return minutes
        }
        return targetMinutes(for: period)
    }

    func effectiveDailyTargetMinutes(on dayKey: String) -> Int {
        Period.allCases.reduce(0) { $0 + effectiveTargetMinutes(for: $1, on: dayKey) }
    }

    var idleThresholdSeconds: Int {
        get {
            (defaults.object(forKey: "idleThresholdSeconds") as? Int) ?? 300
        }
        set {
            defaults.set(max(0, newValue), forKey: "idleThresholdSeconds")
        }
    }

    var spilloverEnabled: Bool {
        get {
            (defaults.object(forKey: "spilloverEnabled") as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: "spilloverEnabled")
        }
    }

    private func targetKey(_ period: Period) -> String {
        "target_\(period.rawValue)_minutes"
    }
}
