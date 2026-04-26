import Foundation

final class HistoryStore {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var entries: [String: Int] = [:]
    private let storeURL: URL
    private var dirtySinceSave: Int = 0
    private let saveEvery: Int = 60

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
        let key = Self.dayFormatter.string(from: date)
        entries[key, default: 0] += 1
        dirtySinceSave += 1
        if dirtySinceSave >= saveEvery {
            save()
            dirtySinceSave = 0
        }
    }

    func seconds(forDay date: Date) -> Int {
        return entries[Self.dayFormatter.string(from: date)] ?? 0
    }

    func entries(forMonth month: Date) -> [Date: Int] {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month], from: month)
        components.day = 1
        guard let monthStart = cal.date(from: components),
              let range = cal.range(of: .day, in: .month, for: monthStart) else {
            return [:]
        }
        var result: [Date: Int] = [:]
        for day in range {
            components.day = day
            guard let date = cal.date(from: components) else { continue }
            let key = Self.dayFormatter.string(from: date)
            if let value = entries[key], value > 0 {
                result[date] = value
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

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
