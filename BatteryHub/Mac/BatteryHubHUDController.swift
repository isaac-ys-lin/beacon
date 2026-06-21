import AppKit
import SwiftUI
import os

@MainActor
final class BatteryHubHUDController {
    private let logger = Logger(subsystem: "com.isaacyslin.BatteryHub.mac", category: "hud")
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    func show(event: BatteryAlertEvent) {
        guard BatteryHUDPreferences.isEnabled(for: event.kind) else { return }
        let percent = event.percent ?? -1
        logger.info("HUD shown kind=\(event.kind.telemetryName, privacy: .public) percent=\(percent, privacy: .public)")

        let window = existingOrNewWindow()
        let hostingController = NSHostingController(
            rootView: BatteryActionHUDView(
                event: event,
                showsDismissButton: BatteryHUDPreferences.showsDismissButton(),
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        )
        hostingController.view.frame = NSRect(origin: .zero, size: Self.hudSize)
        window.contentViewController = hostingController
        applyRoundedTransparentMask(to: hostingController.view)
        applyRoundedTransparentMask(to: window.contentView)
        position(window)

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }

        scheduleAutoDismiss(for: window)
    }

    private func scheduleAutoDismiss(for window: NSWindow) {
        dismissTask?.cancel()
        guard BatteryHUDPreferences.isAutoDismissEnabled() else {
            dismissTask = nil
            return
        }

        let delay = BatteryHUDPreferences.dismissDelaySeconds()
        dismissTask = Task { [weak self, weak window] in
            try? await Task.sleep(for: .seconds(delay))
            await MainActor.run {
                guard let self, let window, window == self.window else { return }
                self.dismiss()
            }
        }
    }

    private func dismiss() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
            }
        }
    }

    private func existingOrNewWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 92),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.window = window
        return window
    }

    private static let hudSize = NSSize(width: 520, height: 92)

    private func applyRoundedTransparentMask(to view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = BatteryActionHUDView.cornerRadius
        if #available(macOS 10.15, *) {
            view.layer?.cornerCurve = .continuous
        }
        view.layer?.masksToBounds = true
    }

    private func position(_ window: NSWindow) {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.hudSize
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 42
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

private extension BatteryAlertKind {
    var telemetryName: String {
        switch self {
        case .lowBattery:
            return "lowBattery"
        case .charged:
            return "charged"
        }
    }
}
