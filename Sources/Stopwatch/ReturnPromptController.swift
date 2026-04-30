import AppKit
import SwiftUI

struct ReturnPromptView: View {
    let extraAwaySeconds: Int
    let onChoice: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                Button("Keep") { onChoice(true) }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
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

private final class PromptPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ReturnPromptController: NSObject {
    private var window: PromptPanelWindow?
    private var pendingHandler: ((Bool) -> Void)?

    func show(
        extraAwaySeconds: Int,
        relativeTo view: NSView,
        onChoice: @escaping (Bool) -> Void
    ) {
        dismissAsDiscard()

        guard let buttonWindow = view.window else {
            onChoice(false)
            return
        }

        pendingHandler = onChoice

        let promptView = ReturnPromptView(extraAwaySeconds: extraAwaySeconds) { [weak self] keep in
            self?.handleChoice(keep)
        }

        let hosting = NSHostingView(rootView: promptView)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        let anchor = buttonWindow.convertToScreen(view.bounds)
        let frame = NSRect(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - size.height,
            width: size.width,
            height: size.height
        )

        let win = PromptPanelWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .popUpMenu
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        win.hidesOnDeactivate = false
        win.becomesKeyOnlyIfNeeded = true
        win.animationBehavior = .utilityWindow

        let veView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        veView.autoresizingMask = [.width, .height]
        veView.material = .menu
        veView.blendingMode = .behindWindow
        veView.state = .active
        veView.wantsLayer = true
        veView.layer?.cornerRadius = 8
        veView.layer?.masksToBounds = true

        hosting.frame = veView.bounds
        hosting.autoresizingMask = [.width, .height]
        veView.addSubview(hosting)
        win.contentView = veView

        window = win

        win.orderFrontRegardless()
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    private func handleChoice(_ keep: Bool) {
        let handler = pendingHandler
        pendingHandler = nil
        close()
        handler?(keep)
    }

    private func dismissAsDiscard() {
        guard let handler = pendingHandler else {
            close()
            return
        }
        pendingHandler = nil
        close()
        handler(false)
    }
}
