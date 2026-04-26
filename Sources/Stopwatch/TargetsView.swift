import AppKit
import SwiftUI

struct TargetsView: View {
    @State private var morningHours: Int
    @State private var morningMinutes: Int
    @State private var afternoonHours: Int
    @State private var afternoonMinutes: Int
    @State private var nightHours: Int
    @State private var nightMinutes: Int

    init() {
        let prefs = Preferences.shared
        let m = prefs.targetMinutes(for: .morning)
        let a = prefs.targetMinutes(for: .afternoon)
        let n = prefs.targetMinutes(for: .night)
        _morningHours = State(initialValue: m / 60)
        _morningMinutes = State(initialValue: m % 60)
        _afternoonHours = State(initialValue: a / 60)
        _afternoonMinutes = State(initialValue: a % 60)
        _nightHours = State(initialValue: n / 60)
        _nightMinutes = State(initialValue: n % 60)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily Targets")
                .font(.headline)
            Text("Set 0 to disable a period. The daily total auto-sums the three periods — when met it fires a big firework; each period fires a smaller one. Periods are 5 AM–noon, noon–6 PM, and 6 PM–5 AM.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
            row(
                label: "Afternoon",
                hours: $afternoonHours,
                minutes: $afternoonMinutes,
                onChange: { save(.afternoon, hours: afternoonHours, minutes: afternoonMinutes) }
            )
            row(
                label: "Night",
                hours: $nightHours,
                minutes: $nightMinutes,
                onChange: { save(.night, hours: nightHours, minutes: nightMinutes) }
            )

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
        Preferences.shared.setTargetMinutes(hours * 60 + minutes, for: period)
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
