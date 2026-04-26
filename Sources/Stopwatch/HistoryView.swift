import AppKit
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore
    @State private var displayedMonth: Date = HistoryView.firstDayOfCurrentMonth()

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayHeader
            calendarGrid
            Spacer(minLength: 0)
            Text(monthSummary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 380, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            Spacer()
            Text(monthLabel)
                .font(.headline)
            Spacer()
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(monthCells) { cell in
                DayCell(cell: cell, maxSeconds: maxSecondsInMonth)
            }
        }
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        let symbols = f.veryShortStandaloneWeekdaySymbols ?? ["S","M","T","W","T","F","S"]
        return Array(symbols.prefix(7))
    }

    private var monthEntries: [Date: Int] {
        store.entries(forMonth: displayedMonth)
    }

    private var maxSecondsInMonth: Int {
        max(1, monthEntries.values.max() ?? 1)
    }

    private var monthCells: [MonthCell] {
        let cal = Calendar.current
        let firstWeekday = cal.component(.weekday, from: displayedMonth)
        guard let range = cal.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        var cells: [MonthCell] = []
        let leadingBlanks = firstWeekday - cal.firstWeekday
        let normalizedLeading = (leadingBlanks + 7) % 7
        for i in 0..<normalizedLeading {
            cells.append(MonthCell(id: "blank-lead-\(i)", date: nil, day: nil, seconds: 0))
        }
        var components = cal.dateComponents([.year, .month], from: displayedMonth)
        for day in range {
            components.day = day
            guard let date = cal.date(from: components) else { continue }
            let secs = store.seconds(forDay: date)
            cells.append(MonthCell(id: "day-\(day)", date: date, day: day, seconds: secs))
        }
        let totalCells = 42
        while cells.count < totalCells {
            cells.append(MonthCell(id: "blank-trail-\(cells.count)", date: nil, day: nil, seconds: 0))
        }
        return cells
    }

    private var monthSummary: String {
        let total = monthEntries.values.reduce(0, +)
        let h = total / 3600
        let m = (total % 3600) / 60
        return "Total this month: \(h)h \(String(format: "%02d", m))m"
    }

    private func previousMonth() {
        if let d = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = d
        }
    }

    private func nextMonth() {
        if let d = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = d
        }
    }

    private static func firstDayOfCurrentMonth() -> Date {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: components) ?? Date()
    }
}

struct MonthCell: Identifiable {
    let id: String
    let date: Date?
    let day: Int?
    let seconds: Int
}

struct DayCell: View {
    let cell: MonthCell
    let maxSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let day = cell.day {
                Text("\(day)")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Text(cell.seconds > 0 ? formattedDuration : "—")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text(" ")
                    .font(.system(size: 11))
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(background)
        .cornerRadius(4)
    }

    private var formattedDuration: String {
        let h = cell.seconds / 3600
        let m = (cell.seconds % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    private var intensity: Double {
        guard cell.seconds > 0, maxSeconds > 0 else { return 0 }
        return min(1.0, Double(cell.seconds) / Double(maxSeconds))
    }

    private var background: Color {
        if cell.day == nil { return Color.clear }
        if cell.seconds == 0 { return Color.primary.opacity(0.06) }
        return Color.accentColor.opacity(0.22 + intensity * 0.55)
    }
}
