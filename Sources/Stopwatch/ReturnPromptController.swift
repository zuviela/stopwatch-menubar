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
                    .keyboardShortcut(.cancelAction)
                Button("Keep") { onChoice(true) }
                    .keyboardShortcut(.defaultAction)
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

private final class PromptPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ReturnPromptController: NSObject {
    private var window: PromptPanelWindow?
    private var pendingHandler: ((Bool) -> Void)?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

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
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .popUpMenu
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.transient, .ignoresCycle]
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

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        installEventMonitors()
    }

    func close() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        localKeyMonitor = nil

        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            resignKeyObserver = nil
        }

        window?.orderOut(nil)
        window = nil
    }

    private func installEventMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.dismissAsDiscard()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            if event.window !== self?.window {
                self?.dismissAsDiscard()
            }
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                self?.handleChoice(false)
                return nil
            }
            return event
        }

        if let win = window {
            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: win,
                queue: .main
            ) { [weak self] _ in
                self?.dismissAsDiscard()
            }
        }
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
