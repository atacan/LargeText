import AppKit
import LargeTextCore
import os

/// The live `NoticePresenting`: a large, click-through HUD on the screen under the mouse.
/// Auto-hides after `displayDuration`; a new notice replaces the current one and restarts the timer.
@MainActor
package final class HUDNoticePresenter: NoticePresenting {
    private let displayDuration: Duration

    private var panel: HUDPanel?
    private var stack: NSStackView?
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private var hideTask: Task<Void, Never>?

    package init(displayDuration: Duration = Theme.hudDisplayDuration) {
        self.displayDuration = displayDuration
    }

    package func show(_ notice: Notice) {
        let content = NoticeContent(notice)
        Logger.ui.info("HUD: \(content.title, privacy: .public)")
        let panel = makePanelIfNeeded()

        titleLabel.stringValue = content.title
        subtitleLabel.stringValue = content.subtitle ?? ""
        subtitleLabel.isHidden = content.subtitle == nil

        if let screen = NSScreen.resolve(targetFrame: nil), let stack {
            let visible = screen.visibleFrame
            let maxTextWidth = visible.width * Theme.hudMaxWidthFraction - Theme.hudPadding * 2
            titleLabel.preferredMaxLayoutWidth = maxTextWidth
            subtitleLabel.preferredMaxLayoutWidth = maxTextWidth
            let fitting = stack.fittingSize
            let size = NSSize(
                width: (fitting.width + Theme.hudPadding * 2).rounded(.up),
                height: (fitting.height + Theme.hudPadding * 2).rounded(.up)
            )
            let origin = NSPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.midY - size.height / 2).rounded()
            )
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak self, displayDuration] in
            try? await Task.sleep(for: displayDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func hide() {
        hideTask = nil
        panel?.orderOut(nil)
    }

    private func makePanelIfNeeded() -> HUDPanel {
        if let panel { return panel }
        let panel = HUDPanel()

        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.maskImage = Theme.roundedMask(cornerRadius: Theme.hudCornerRadius)
        card.appearance = NSAppearance(named: .darkAqua)

        titleLabel.font = .systemFont(ofSize: Theme.hudTitleSize, weight: .bold)
        titleLabel.textColor = Theme.textColor
        titleLabel.alignment = .center
        subtitleLabel.font = .systemFont(ofSize: Theme.hudSubtitleSize, weight: .medium)
        subtitleLabel.textColor = Theme.hudSubtitleColor
        subtitleLabel.alignment = .center

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        let padding = Theme.hudPadding
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),
        ])

        panel.contentView = card
        self.panel = panel
        self.stack = stack
        return panel
    }
}
