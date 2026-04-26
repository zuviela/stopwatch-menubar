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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Targets by Period")
                .font(.headline)
            Text("Set 0 for any period to disable its target. Periods are 5 AM–noon, noon–6 PM, and 6 PM–5 AM.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        .frame(width: 380, height: 280)
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
