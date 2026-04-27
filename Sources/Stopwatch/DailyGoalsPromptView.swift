import AppKit
import SwiftUI

struct DailyGoalsPromptView: View {
    @State private var morningHours: Int
    @State private var morningMinutes: Int
    @State private var afternoonHours: Int
    @State private var afternoonMinutes: Int
    @State private var nightHours: Int
    @State private var nightMinutes: Int

    private let dayLabel: String
    private let onConfirm: ([Period: Int]) -> Void
    private let onCancel: () -> Void

    init(
        prefill: [Period: Int],
        dayLabel: String,
        onConfirm: @escaping ([Period: Int]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let m = prefill[.morning] ?? 0
        let a = prefill[.afternoon] ?? 0
        let n = prefill[.night] ?? 0
        _morningHours = State(initialValue: m / 60)
        _morningMinutes = State(initialValue: m % 60)
        _afternoonHours = State(initialValue: a / 60)
        _afternoonMinutes = State(initialValue: a % 60)
        _nightHours = State(initialValue: n / 60)
        _nightMinutes = State(initialValue: n % 60)
        self.dayLabel = dayLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
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
            Text("Set goals for \(dayLabel)")
                .font(.headline)
            Text("These lock when you start the timer — you won't be able to change today's goals until tomorrow. Set 0 to disable a period.")
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

            row(label: "Morning", hours: $morningHours, minutes: $morningMinutes)
            row(label: "Afternoon", hours: $afternoonHours, minutes: $afternoonMinutes)
            row(label: "Night", hours: $nightHours, minutes: $nightMinutes)

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Lock In & Start") {
                    let goals: [Period: Int] = [
                        .morning: morningHours * 60 + morningMinutes,
                        .afternoon: afternoonHours * 60 + afternoonMinutes,
                        .night: nightHours * 60 + nightMinutes
                    ]
                    onConfirm(goals)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func row(label: String, hours: Binding<Int>, minutes: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 84, alignment: .leading)
            Stepper("\(hours.wrappedValue) h", value: hours, in: 0...23)
                .frame(width: 110)
            Stepper("\(minutes.wrappedValue) m", value: minutes, in: 0...55, step: 5)
                .frame(width: 110)
        }
    }
}

final class DailyGoalsPromptController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onConfirm: (([Period: Int]) -> Void)?
    private var onCancel: (() -> Void)?

    func show(
        prefill: [Period: Int],
        dayLabel: String,
        onConfirm: @escaping ([Period: Int]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        if let win = window {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        self.onConfirm = onConfirm
        self.onCancel = onCancel

        let view = DailyGoalsPromptView(
            prefill: prefill,
            dayLabel: dayLabel,
            onConfirm: { [weak self] goals in
                self?.handleConfirm(goals)
            },
            onCancel: { [weak self] in
                self?.handleCancel()
            }
        )
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "Today's Goals"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func handleConfirm(_ goals: [Period: Int]) {
        let cb = onConfirm
        onConfirm = nil
        onCancel = nil
        closeWindow()
        cb?(goals)
    }

    private func handleCancel() {
        let cb = onCancel
        onConfirm = nil
        onCancel = nil
        closeWindow()
        cb?()
    }

    private func closeWindow() {
        let w = window
        window = nil
        w?.delegate = nil
        w?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if onCancel != nil {
            handleCancel()
        }
    }
}
