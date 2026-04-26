import AppKit
import SwiftUI

struct ReturnPromptView: View {
    let extraAwaySeconds: Int
    let onChoice: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome back")
                .font(.headline)
            Text("You stepped away for an extra **\(formatted)** after the timer paused.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("Add that to your tracked time?")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("Discard") { onChoice(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Keep") { onChoice(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var formatted: String {
        let h = extraAwaySeconds / 3600
        let m = (extraAwaySeconds % 3600) / 60
        let s = extraAwaySeconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m) min" }
        return "\(s)s"
    }
}

final class ReturnPromptController: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var pendingHandler: ((Bool) -> Void)?

    func show(
        extraAwaySeconds: Int,
        relativeTo view: NSView,
        onChoice: @escaping (Bool) -> Void
    ) {
        close()
        pendingHandler = onChoice

        let promptView = ReturnPromptView(extraAwaySeconds: extraAwaySeconds) { [weak self] keep in
            self?.handleChoice(keep)
        }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: promptView)
        pop.delegate = self

        NSApp.activate(ignoringOtherApps: true)
        pop.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        popover = pop
    }

    func close() {
        popover?.close()
        popover = nil
    }

    private func handleChoice(_ keep: Bool) {
        let handler = pendingHandler
        pendingHandler = nil
        close()
        handler?(keep)
    }

    func popoverDidClose(_ notification: Notification) {
        if let handler = pendingHandler {
            pendingHandler = nil
            handler(false)
        }
        popover = nil
    }
}
