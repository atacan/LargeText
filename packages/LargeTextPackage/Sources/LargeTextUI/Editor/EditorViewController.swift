import AppKit
import LargeTextCore

/// Backdrop, card, header, `LargeTextView`, footer. Renders an `OverlayChrome` and maps
/// `EditorAction`s to intent kinds (tagged with the session by `OverlayWindowController`) or local edits.
@MainActor
package final class EditorViewController: NSViewController, NSTextViewDelegate {
    /// Commit / cancel / zoom requests. Not tagged with a session; the window controller does that.
    package var onIntent: ((OverlayIntent.Kind) -> Void)?

    package let textView = LargeTextView.make()

    private let scrollView = NSScrollView()
    private let card = CardView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: EditorStrings.neutralTitle)
    private let hintsLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(labelWithString: EditorStrings.footer)

    private var editorHeight: NSLayoutConstraint?
    private var iconWidth: NSLayoutConstraint?
    private var iconHeight: NSLayoutConstraint?

    private var chrome = OverlayChrome(fontSize: FontSize(points: 64))
    /// Outer optional: "not resolved yet"; inner: the bundle id the current icon belongs to.
    private var iconBundleIdentifier: String??

    package init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Public API

    /// Re-renders everything except the text.
    package func render(_ chrome: OverlayChrome) {
        self.chrome = chrome
        _ = view
        applyChrome()
    }

    /// Replaces the text (once per session) and selects all of it, like a URL bar.
    package func setInitialText(_ text: String) {
        _ = view
        textView.string = text
        textView.applyFont(editorFont)
        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        updateEditorHeight()
    }

    // MARK: - View

    override package func loadView() {
        let backdrop = BackdropView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        backdrop.autoresizingMask = [.width, .height]
        backdrop.appearance = NSAppearance(named: .darkAqua)
        backdrop.onClick = { [weak self] in self?.onIntent?(.cancel(.userCancelled)) }
        view = backdrop
        buildCard(in: backdrop)
        applyChrome()
    }

    override package func viewDidLayout() {
        super.viewDidLayout()
        updateEditorHeight()
    }

    private func buildCard(in container: NSView) {
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.maskImage = Theme.roundedMask(cornerRadius: Theme.cardCornerRadius)
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.textColor = Theme.headerColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        hintsLabel.textColor = Theme.hintColor
        hintsLabel.lineBreakMode = .byWordWrapping
        hintsLabel.maximumNumberOfLines = 0

        footerLabel.textColor = Theme.footerColor
        footerLabel.lineBreakMode = .byWordWrapping
        footerLabel.maximumNumberOfLines = 0

        textView.delegate = self
        textView.onAction = { [weak self] action in self?.handle(action) }

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let headerRow = NSStackView(views: [iconView, titleLabel])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12

        let stack = NSStackView(views: [headerRow, hintsLabel, scrollView, footerLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Theme.cardSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let padding = Theme.cardPadding
        let editorHeight = scrollView.heightAnchor.constraint(equalToConstant: 80)
        // Yields to the card's max height at huge font sizes on small screens (then the editor scrolls).
        editorHeight.priority = NSLayoutConstraint.Priority(999)
        let iconWidth = iconView.widthAnchor.constraint(equalToConstant: 32)
        let iconHeight = iconView.heightAnchor.constraint(equalToConstant: 32)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            card.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: Theme.cardWidthFraction),
            card.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, multiplier: 0.95),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),

            headerRow.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            hintsLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footerLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            editorHeight,
            iconWidth,
            iconHeight,
        ])
        self.editorHeight = editorHeight
        self.iconWidth = iconWidth
        self.iconHeight = iconHeight
    }

    // MARK: - Rendering

    private var editorFont: NSFont {
        Theme.editorFont(size: CGFloat(chrome.fontSize.points))
    }

    private func applyChrome() {
        guard isViewLoaded else { return }
        let size = CGFloat(chrome.fontSize.points)
        let headerSize = (size * Theme.headerScale).rounded()
        let footerSize = (size * Theme.footerScale).rounded()

        textView.applyFont(editorFont)

        titleLabel.font = Theme.headerFont(size: headerSize)
        titleLabel.stringValue = EditorStrings.title(targetName: chrome.targetName)

        let hints = EditorStrings.hints(chrome.hints)
        hintsLabel.font = Theme.headerFont(size: (headerSize * 0.8).rounded())
        hintsLabel.stringValue = hints.joined(separator: "  ·  ")
        hintsLabel.isHidden = hints.isEmpty

        footerLabel.font = Theme.footerFont(size: footerSize)

        updateIcon()
        let iconEdge = (headerSize * Theme.iconScale).rounded()
        iconWidth?.constant = iconEdge
        iconHeight?.constant = iconEdge

        updateEditorHeight()
    }

    private func updateIcon() {
        let bundleIdentifier = chrome.targetBundleIdentifier
        if let resolved = iconBundleIdentifier, resolved == bundleIdentifier { return }
        iconBundleIdentifier = .some(bundleIdentifier)
        let image = Self.applicationIcon(bundleIdentifier: bundleIdentifier)
        iconView.image = image
        iconView.isHidden = image == nil
    }

    private static func applicationIcon(bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Grows the editor with its content up to `editorMaxHeightFraction` of the screen, then scrolls.
    private func updateEditorHeight() {
        guard isViewLoaded,
              let editorHeight,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }
        layoutManager.ensureLayout(for: container)
        let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? editorFont)
        let inset = textView.textContainerInset.height * 2
        let content = max(layoutManager.usedRect(for: container).height, lineHeight) + inset
        let limit = max(lineHeight + inset, (view.bounds.height * Theme.editorMaxHeightFraction).rounded(.down))
        let height = min(content, limit).rounded(.up)
        scrollView.hasVerticalScroller = content > limit
        if abs(editorHeight.constant - height) > 0.5 {
            editorHeight.constant = height
        }
    }

    // MARK: - Actions

    private func handle(_ action: EditorAction) {
        switch action {
        case .commit(let mode): onIntent?(.commit(mode))
        case .cancel: onIntent?(.cancel(.userCancelled))
        case .zoom(let step): onIntent?(.zoom(step))
        case .newline: textView.insertNewlineIgnoringFieldEditor(nil)
        case .standardEdit(let edit): textView.perform(edit)
        }
    }

    // MARK: - NSTextViewDelegate

    package func textDidChange(_ notification: Notification) {
        updateEditorHeight()
    }
}
