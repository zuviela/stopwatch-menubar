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
}
