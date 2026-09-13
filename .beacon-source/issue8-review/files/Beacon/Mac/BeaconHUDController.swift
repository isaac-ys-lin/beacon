import AppKit
import SwiftUI
import os

@MainActor
final class BeaconHUDController {
    private let logger = Logger(subsystem: "com.isaacyslin.Beacon.mac", category: "hud")
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?
    private var presentationID = 0
    private var queue = BeaconHUDQueue()
    private let defaults: UserDefaults
    private var isUITestPresentation = false
    var onReviewOperation: ((String) -> Void)?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    #if DEBUG
    var debugWindow: NSPanel? { window as? NSPanel }
    var debugCurrentEvent: BeaconHUDEvent? { queue.current?.event }
    func debugDismiss() { dismiss() }
    #endif

    func show(event: BatteryAlertEvent) {
        guard BatteryHUDPreferences.isEnabled(for: event.kind, defaults: defaults) else { return }
        enqueue(.battery(event))
    }

    func show(operation: BluetoothConnectionOperation) {
        guard BatteryHUDPreferences.isEnabled(defaults: defaults) else { return }
        enqueue(.connection(operation))
    }

    func refreshPreferences() {
        if !BatteryHUDPreferences.isEnabled(defaults: defaults) && !isUITestPresentation {
            queue = BeaconHUDQueue()
            hideWindow()
        } else if queue.current != nil {
            renderCurrent()
        }
    }

    private func enqueue(_ event: BeaconHUDEvent) {
        let previous = queue.current
        queue.submit(event)
        if previous != queue.current { renderCurrent() }
    }

    #if DEBUG
    /// Deterministic preview path for focus/UI verification. It intentionally
    /// bypasses user HUD preferences without mutating them.
    func showForUITesting(event: BatteryAlertEvent) {
        // UI automation can spend several seconds establishing its accessibility
        // session after launch, especially on hosted macOS runners.
        isUITestPresentation = true
        enqueue(.battery(event))
    }

    func prepareOperationUITesting() { isUITestPresentation = true }

    func exposeWindowToAccessibilityForUITesting() {
        guard let window else { return }
        window.styleMask.remove(.nonactivatingPanel)
        window.styleMask.formUnion([.titled, .fullSizeContentView])
        window.title = BeaconL10n.string("Beacon HUD Preview")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(contentSize)
        window.makeKeyAndOrderFront(nil)
    }
    #endif

    private var contentSize: NSSize {
        NSSize(width: 520, height: queue.current?.event.operation == nil ? 92 : 150)
    }

    private func renderCurrent() {
        guard let entry = queue.current else { hideWindow(); return }
        presentationID += 1
        let window = existingOrNewWindow()
        let showsDismiss = isUITestPresentation || BatteryHUDPreferences.showsDismissButton(defaults: defaults)
        let view: AnyView
        switch entry.event {
        case let .battery(event):
            logger.info("Battery reminder presented")
            view = AnyView(BatteryActionHUDView(event: event, showsDismissButton: showsDismiss,
                onDismiss: { [weak self] in self?.dismiss() }))
        case let .connection(operation):
            logger.info("Connection operation presented phase=\(operation.phase.rawValue, privacy: .public)")
            view = AnyView(ConnectionActionHUDView(operation: operation, showsDismissButton: showsDismiss,
                onDismiss: { [weak self] in self?.dismiss() },
                onReview: { [weak self] in self?.onReviewOperation?(operation.deviceID) }))
        }
        let hostingController = NSHostingController(rootView: view)
        hostingController.view.frame = NSRect(origin: .zero, size: contentSize)
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

        // Progress lasts until the bounded operation completes. Every terminal result
        // receives its own full configured interval, even after queued battery events.
        let delay: Double? = entry.event.operation?.phase.isInProgress == true ? nil
            : isUITestPresentation ? 6
            : BatteryHUDPreferences.isAutoDismissEnabled(defaults: defaults)
                ? BatteryHUDPreferences.dismissDelaySeconds(defaults: defaults) : nil
        scheduleAutoDismiss(for: window, delay: delay)
    }

    private func scheduleAutoDismiss(for window: NSWindow, delay: Double?) {
        dismissTask?.cancel()
        guard let delay else {
            dismissTask = nil
            return
        }

        let scheduledPresentationID = presentationID
        dismissTask = Task { [weak self, weak window] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled, let self, let window, window == self.window,
                  scheduledPresentationID == self.presentationID else { return }
            self.dismiss()
        }
    }

    private func dismiss() {
        queue.dismiss()
        if queue.current != nil { renderCurrent() } else { hideWindow() }
    }

    private func hideWindow() {
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

    private func existingOrNewWindow() -> NSWindow {
        if let window {
            return window
        }

        #if DEBUG
        let isUITestWindow = ProcessInfo.processInfo.arguments.contains("--ui-test-show-hud")
        #else
        let isUITestWindow = false
        #endif

        let contentRect = NSRect(x: 0, y: 0, width: 520, height: 92)
        let window: NSWindow = isUITestWindow
            ? NSWindow(
                contentRect: contentRect,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            : BeaconHUDPanel(
                contentRect: contentRect,
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
        (window as? NSPanel)?.becomesKeyOnlyIfNeeded = true
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.window = window
        return window
    }

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
        let size = contentSize
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
