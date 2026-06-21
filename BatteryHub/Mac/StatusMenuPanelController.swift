import AppKit
import SwiftUI

@MainActor
final class StatusMenuPanelController {
    private(set) var hostingController: NSHostingController<StatusMenuView>?
    private(set) var panel: BatteryHubStatusPanel?
    private var contentSize: NSSize = StatusMenuSizing.preferredContentSize(
        dashboardItemCount: 0,
        showsOverview: false,
        visibleScreenHeight: 900
    )

    var isShown: Bool {
        panel?.isVisible == true
    }

    func install(rootView: StatusMenuView, contentSize: NSSize) {
        self.contentSize = contentSize
        if let hostingController {
            hostingController.rootView = rootView
            hostingController.view.frame = NSRect(origin: .zero, size: contentSize)
            applyRoundedMask(to: hostingController.view)
            applyRoundedMask(to: panel?.contentView)
            panel?.setContentSize(contentSize)
            return
        }

        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController
        hostingController.view.frame = NSRect(origin: .zero, size: contentSize)
        applyRoundedMask(to: hostingController.view)

        let panel = BatteryHubStatusPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = hostingController
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        applyRoundedMask(to: panel.contentView)
        self.panel = panel
    }

    func show(relativeTo sender: NSStatusBarButton) {
        guard let panel else { return }
        guard let window = sender.window else {
            panel.center()
            panel.orderFrontRegardless()
            return
        }

        let buttonFrame = window.convertToScreen(sender.convert(sender.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let frame = StatusMenuPanelPositioning.frame(
            contentSize: contentSize,
            buttonFrame: buttonFrame,
            visibleFrame: visibleFrame
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func applyRoundedMask(to view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = NativeMacStyle.popoverCornerRadius
        if #available(macOS 10.15, *) {
            view.layer?.cornerCurve = .continuous
        }
        view.layer?.masksToBounds = true
    }
}

final class BatteryHubStatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum StatusMenuPanelPositioning {
    static let margin: CGFloat = 8
    static let verticalGap: CGFloat = 6

    static func frame(
        contentSize: NSSize,
        buttonFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return NSRect(
                x: buttonFrame.midX - contentSize.width / 2,
                y: buttonFrame.minY - contentSize.height - verticalGap,
                width: contentSize.width,
                height: contentSize.height
            )
        }

        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - contentSize.width - margin
        let proposedX = buttonFrame.midX - contentSize.width / 2
        let x = min(max(proposedX, minX), max(minX, maxX))

        let minY = visibleFrame.minY + margin
        let maxY = visibleFrame.maxY - contentSize.height - margin
        let proposedY = buttonFrame.minY - contentSize.height - verticalGap
        let y = min(max(proposedY, minY), max(minY, maxY))

        return NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height)
    }
}

private extension NSSize {
    func isApproximatelyEqual(to other: NSSize) -> Bool {
        abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}
