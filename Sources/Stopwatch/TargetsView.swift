import AppKit
import SwiftUI

struct TargetsView: View {
    @State private var morningHours: Int
    @State private var morningMinutes: Int
    @State private var afternoonHours: Int
    @State private var afternoonMinutes: Int
    @State private var nightHours: Int
    @State private var nightMinutes: Int
    @State private var isLocked: Bool

    init() {
        let prefs = Preferences.shared
        let dayKey = HistoryStore.dayKey(for: Date())
        let locked = prefs.goalsAreLocked(for: dayKey)
        let lockedValues = prefs.lockedGoals(for: dayKey)
        let m = locked ? (lockedValues?[.morning] ?? 0) : prefs.targetMinutes(for: .morning)
        let a = locked ? (lockedValues?[.afternoon] ?? 0) : prefs.targetMinutes(for: .afternoon)
        let n = locked ? (lockedValues?[.night] ?? 0) : prefs.targetMinutes(for: .night)
        _morningHours = State(initialValue: m / 60)
        _morningMinutes = State(initialValue: m % 60)
        _afternoonHours = State(initialValue: a / 60)
        _afternoonMinutes = State(initialValue: a % 60)
        _nightHours = State(initialValue: n / 60)
        _nightMinutes = State(initialValue: n % 60)
        _isLocked = State(initialValue: locked)
    }

    private var dailyTotalMinutes: Int {
        morningHours * 60 + morningMinutes
            + afternoonHours * 60 + afternoonMinutes
            + nightHours * 60 + nightMinutes
    }

    private var dailyTotalLabel: String {
        let h = dailyTotalMinutes / 60
        let m = dailyTotalMinutes % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return "\(m)m"
    }

    private var todayLockBannerText: String? {
        guard isLocked else { return nil }
        func fmt(_ minutes: Int) -> String {
            let h = minutes / 60
            let m = minutes % 60
            if h > 0 && m > 0 { return "\(h)h\(m)m" }
            if h > 0 { return "\(h)h" }
            return "\(m)m"
        }
        let m = morningHours * 60 + morningMinutes
        let a = afternoonHours * 60 + afternoonMinutes
        let n = nightHours * 60 + nightMinutes
        return "Locked until 4 AM: Morning \(fmt(m)) · Afternoon \(fmt(a)) · Night \(fmt(n)). They'll unlock automatically for the next day."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily Targets")
                .font(.headline)
            Text("Set 0 to disable a period. The daily total auto-sums the three periods — when met it fires a big firework; each period fires a smaller one. Periods are 5 AM–noon, noon–6 PM, and 6 PM–5 AM.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let banner = todayLockBannerText {
                Text(banner)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Daily Total (auto)")
                    .frame(width: 152, alignment: .leading)
                Text(dailyTotalLabel)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }

            Divider()

            row(
                label: "Morning",
                hours: $morningHours,
                minutes: $morningMinutes,
                onChange: { save(.morning, hours: morningHours, minutes: morningMinutes) }
            )
            .disabled(isLocked)
            row(
                label: "Afternoon",
                hours: $afternoonHours,
                minutes: $afternoonMinutes,
                onChange: { save(.afternoon, hours: afternoonHours, minutes: afternoonMinutes) }
            )
            .disabled(isLocked)
            row(
                label: "Night",
                hours: $nightHours,
                minutes: $nightMinutes,
                onChange: { save(.night, hours: nightHours, minutes: nightMinutes) }
            )
            .disabled(isLocked)

            Divider()

            HStack {
                Spacer()
                if isLocked {
                    Text("Locked until 4 AM")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    Button("Lock targets for today") {
                        lockToday()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func row(
        label: String,
        hours: Binding<Int>,
        minutes: Binding<Int>,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 84, alignment: .leading)
            Stepper(
                "\(hours.wrappedValue) h",
                value: hours,
                in: 0...23,
                onEditingChanged: { _ in onChange() }
            )
            .onChange(of: hours.wrappedValue) { _, _ in onChange() }
            .frame(width: 110)
            Stepper(
                "\(minutes.wrappedValue) m",
                value: minutes,
                in: 0...55,
                step: 5,
                onEditingChanged: { _ in onChange() }
            )
            .onChange(of: minutes.wrappedValue) { _, _ in onChange() }
            .frame(width: 110)
        }
    }

    private func save(_ period: Period, hours: Int, minutes: Int) {
        guard !isLocked else { return }
        Preferences.shared.setTargetMinutes(hours * 60 + minutes, for: period)
    }

    private func lockToday() {
        let goals: [Period: Int] = [
            .morning: morningHours * 60 + morningMinutes,
            .afternoon: afternoonHours * 60 + afternoonMinutes,
            .night: nightHours * 60 + nightMinutes
        ]
        let dayKey = HistoryStore.dayKey(for: Date())
        Preferences.shared.lockGoals(goals, for: dayKey)
        isLocked = true
    }
}

final class TargetsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: TargetsView())
            let win = NSWindow(contentViewController: host)
            win.title = "Stopwatch Targets"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
