import AppKit
import Foundation

@MainActor
final class BlockingHUDController {
    private var panel: NSPanel?
    private var dismissalWorkItem: DispatchWorkItem?
    private var shotClockPanel: NSPanel?
    private var shotClockLabel: NSTextField?
    private var extendAction: (() -> Void)?
    private var shieldPanels: [NSPanel] = []
    private var shieldLabels: [NSTextField] = []

    func show(message: String) {
        dismissalWorkItem?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel

        if let textField = panel.contentView?.subviews.first as? NSTextField {
            textField.stringValue = message
        }

        position(panel)
        panel.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        dismissalWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 2.5,
            execute: workItem
        )
    }

    func showShotClock(
        remainingSeconds: TimeInterval,
        onExtend: @escaping () -> Void
    ) {
        let panel = shotClockPanel ?? makeShotClockPanel()
        shotClockPanel = panel
        extendAction = onExtend
        shotClockLabel?.stringValue =
            "\(max(0, Int(remainingSeconds.rounded(.up)))) seconds"
        position(panel)
        panel.orderFrontRegardless()
    }

    func hideShotClock() {
        shotClockPanel?.orderOut(nil)
        extendAction = nil
    }

    func showShield(message: String) {
        if shieldPanels.count != NSScreen.screens.count {
            hideShield()
            for screen in NSScreen.screens {
                let result = makeShieldPanel(for: screen)
                shieldPanels.append(result.panel)
                shieldLabels.append(result.label)
            }
        }

        for (index, panel) in shieldPanels.enumerated() {
            shieldLabels[index].stringValue = message
            panel.orderFrontRegardless()
        }
    }

    func hideShield() {
        for panel in shieldPanels {
            panel.orderOut(nil)
        }
        shieldPanels.removeAll()
        shieldLabels.removeAll()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.96)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 20, y: 16, width: 380, height: 44)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.font = .systemFont(ofSize: 14, weight: .medium)

        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 420, height: 76)
        )
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 14
        contentView.addSubview(label)
        panel.contentView = contentView
        return panel
    }

    private func makeShotClockPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 104),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(
            ofSize: 20,
            weight: .semibold
        )
        label.alignment = .center
        label.frame = NSRect(x: 16, y: 58, width: 278, height: 26)
        shotClockLabel = label

        let button = NSButton(
            title: "+30 seconds",
            target: self,
            action: #selector(extendShotClock)
        )
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.frame = NSRect(x: 85, y: 16, width: 140, height: 34)

        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 310, height: 104)
        )
        contentView.addSubview(label)
        contentView.addSubview(button)
        panel.contentView = contentView
        return panel
    }

    private func makeShieldPanel(
        for screen: NSScreen
    ) -> (panel: NSPanel, label: NSTextField) {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = NSColor(
            calibratedRed: 0.09,
            green: 0.09,
            blue: 0.075,
            alpha: 1
        )
        panel.isOpaque = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.ignoresMouseEvents = true

        let eyebrow = NSTextField(labelWithString: "FOCUS SESSION")
        eyebrow.alignment = .center
        eyebrow.font = .systemFont(ofSize: 13, weight: .bold)
        eyebrow.textColor = NSColor(
            calibratedRed: 0.98,
            green: 0.78,
            blue: 0.42,
            alpha: 1
        )
        eyebrow.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        let guidance = NSTextField(
            labelWithString: "Switch to another app to continue focusing."
        )
        guidance.alignment = .center
        guidance.font = .systemFont(ofSize: 15, weight: .regular)
        guidance.textColor = NSColor.white.withAlphaComponent(0.65)
        guidance.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [eyebrow, label, guidance])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView(frame: screen.frame)
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(
                equalTo: contentView.centerXAnchor
            ),
            stack.centerYAnchor.constraint(
                equalTo: contentView.centerYAnchor
            ),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentView.leadingAnchor,
                constant: 48
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor,
                constant: -48
            ),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 680)
        ])
        panel.contentView = contentView
        return (panel, label)
    }

    @objc
    private func extendShotClock() {
        extendAction?()
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 28
        )
        panel.setFrameOrigin(origin)
    }
}
