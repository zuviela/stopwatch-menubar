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

    var idleThresholdSeconds: Int {
        get {
            (defaults.object(forKey: "idleThresholdSeconds") as? Int) ?? 300
        }
        set {
            defaults.set(max(0, newValue), forKey: "idleThresholdSeconds")
        }
    }

    private func targetKey(_ period: Period) -> String {
        "target_\(period.rawValue)_minutes"
    }
}
