import AppKit
import SwiftUI
import os

@MainActor
final class BeaconHUDController {
    private let logger = Logger(subsystem: "com.isaacyslin.Beacon.mac", category: "hud")
    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var presentationID = 0

    #if DEBUG
    var debugWindow: NSPanel? { window }
    #endif

    func show(event: BatteryAlertEvent) {
        guard BatteryHUDPreferences.isEnabled(for: event.kind) else { return }
        present(
            event: event,
            showsDismissButton: BatteryHUDPreferences.showsDismissButton(),
            autoDismissDelay: BatteryHUDPreferences.isAutoDismissEnabled()
                ? BatteryHUDPreferences.dismissDelaySeconds()
                : nil
        )
    }

    #if DEBUG
    /// Deterministic preview path for focus/UI verification. It intentionally
    /// bypasses user HUD preferences without mutating them.
    func showForUITesting(event: BatteryAlertEvent) {
        // UI automation can spend several seconds establishing its accessibility
        // session after launch, especially on hosted macOS runners.
        present(event: event, showsDismissButton: true, autoDismissDelay: 6)
    }

    func exposeWindowToAccessibilityForUITesting() {
        guard let window else { return }
        window.styleMask.remove(.nonactivatingPanel)
        window.makeKeyAndOrderFront(nil)
    }
    #endif

    private func present(
        event: BatteryAlertEvent,
        showsDismissButton: Bool,
        autoDismissDelay: Double?
    ) {
        let percent = event.percent ?? -1
        logger.info("HUD shown kind=\(event.kind.telemetryName, privacy: .public) percent=\(percent, privacy: .private)")
        presentationID += 1

        let window = existingOrNewWindow()
        let hostingController = NSHostingController(
            rootView: BatteryActionHUDView(
                event: event,
                showsDismissButton: showsDismissButton,
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

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.alphaValue = reduceMotion ? 1 : 0
        window.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                window.animator().alphaValue = 1
            }
        }

        scheduleAutoDismiss(for: window, delay: autoDismissDelay)
    }

    private func scheduleAutoDismiss(for window: NSWindow, delay: Double?) {
        dismissTask?.cancel()
        guard let delay else {
            dismissTask = nil
            return
        }

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
        dismissTask?.cancel()
        dismissTask = nil
        let dismissedPresentationID = presentationID
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                guard dismissedPresentationID == self.presentationID else { return }
                window.orderOut(nil)
            }
        }
    }

    private func existingOrNewWindow() -> NSPanel {
        if let window {
            return window
        }

        let window = BeaconHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
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

private final class BeaconHUDPanel: NSPanel {
    override var canBecomeKey: Bool {
        #if DEBUG
        !styleMask.contains(.nonactivatingPanel)
        #else
        false
        #endif
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
