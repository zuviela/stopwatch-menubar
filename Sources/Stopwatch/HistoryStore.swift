import Foundation

struct PeriodBreakdown {
    let raw: Int
    let effective: Int
    let carryIn: Int
    let carryOut: Int
}

final class HistoryStore {
    static let dayShiftHour: Int = 4

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dayKey(for date: Date) -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        if hour < dayShiftHour {
            let shifted = cal.date(byAdding: .day, value: -1, to: date) ?? date
            return dayFormatter.string(from: shifted)
        }
        return dayFormatter.string(from: date)
    }

    private var entries: [String: [Int]] = [:]
    private let storeURL: URL
    private var dirtySinceSave: Int = 0
    private let saveEvery: Int = 1

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("StopwatchMenuBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storeURL = dir.appendingPathComponent("history.json")
        load()
    }

    func recordSecond(at date: Date) {
        let (key, hour) = bucket(for: date)
        var arr = entries[key] ?? Array(repeating: 0, count: 24)
        if arr.count != 24 { arr = Array(repeating: 0, count: 24) }
        arr[hour] += 1
        entries[key] = arr
        dirtySinceSave += 1
        if dirtySinceSave >= saveEvery {
            save()
            dirtySinceSave = 0
        }
    }

    func subtractSecond(at date: Date) {
        let (key, hour) = bucket(for: date)
        guard var arr = entries[key], arr.count == 24, arr[hour] > 0 else { return }
        arr[hour] -= 1
        entries[key] = arr
        dirtySinceSave += 1
        if dirtySinceSave >= saveEvery {
            save()
            dirtySinceSave = 0
        }
    }

    func seconds(forDay date: Date) -> Int {
        let key = Self.dayKey(for: date)
        return (entries[key] ?? []).reduce(0, +)
    }

    func seconds(forPeriod period: Period, on date: Date) -> Int {
        let key = Self.dayKey(for: date)
        guard let arr = entries[key], arr.count == 24 else { return 0 }
        var total = 0
        for hour in 0..<24 where period.contains(hour: hour) {
            total += arr[hour]
        }
        return total
    }

    func periodBreakdown(on date: Date) -> [Period: PeriodBreakdown] {
        let order: [Period] = [.morning, .afternoon, .night]
        let dayKey = Self.dayKey(for: date)
        var result: [Period: PeriodBreakdown] = [:]
        var carry = 0
        for period in order {
            let raw = seconds(forPeriod: period, on: date)
            let target = Preferences.shared.effectiveTargetMinutes(for: period, on: dayKey) * 60
            let available = raw + carry
            let carryOut: Int
            if target > 0 && available > target {
                carryOut = available - target
            } else {
                carryOut = 0
            }
            result[period] = PeriodBreakdown(
                raw: raw,
                effective: available,
                carryIn: carry,
                carryOut: carryOut
            )
            carry = (period == .night) ? 0 : carryOut
        }
        return result
    }

    func entries(forMonth month: Date) -> [Date: Int] {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month], from: month)
        components.day = 1
        components.hour = 12
        guard let monthStart = cal.date(from: components),
              let range = cal.range(of: .day, in: .month, for: monthStart) else {
            return [:]
        }
        var result: [Date: Int] = [:]
        for day in range {
            components.day = day
            guard let date = cal.date(from: components) else { continue }
            let total = seconds(forDay: date)
            if total > 0 {
                result[date] = total
            }
        }
        return result
    }

    func flush() {
        if dirtySinceSave > 0 {
            save()
            dirtySinceSave = 0
        }
    }

    private func bucket(for date: Date) -> (String, Int) {
        let key = Self.dayKey(for: date)
        let hour = Calendar.current.component(.hour, from: date)
        return (key, hour)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data) {
            entries = decoded.compactMapValues { $0.count == 24 ? $0 : nil }
            return
        }
        if (try? JSONDecoder().decode([String: Int].self, from: data)) != nil {
            FileHandle.standardError.write(
                Data("Stopwatch: discarding pre-v3 per-day history (now per-hour).\n".utf8)
            )
            entries = [:]
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
