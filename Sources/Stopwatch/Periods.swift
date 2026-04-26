import Foundation

enum Period: String, CaseIterable {
    case morning
    case afternoon
    case night

    var label: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .night: return "Night"
        }
    }

    static func current(at date: Date = Date()) -> Period {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return .morning
        case 12..<18: return .afternoon
        default: return .night
        }
    }

    func contains(hour: Int) -> Bool {
        switch self {
        case .morning: return (5...11).contains(hour)
        case .afternoon: return (12...17).contains(hour)
        case .night: return hour >= 18 || hour < 5
        }
    }
}
