import AppKit
import LargeTextCore

/// Backdrop, card, header, `ReaderTextView`, footer. Renders a `ReaderContent` + `ReaderChrome` and maps
/// `ReaderAction`s to intent kinds (tagged with the session by `ReaderWindowController`).
///
/// The card is positioned by frame, not by constraints: `ReaderWindowController` measures it with
/// `preferredCardSize(width:maxHeight:)`, places it with `ReaderPlacement` and applies the result with
/// `setCardFrame(_:)`. The backdrop is only visible while pinned.
@MainActor
package final class ReaderViewController: NSViewController {
    /// Close / zoom requests. Not tagged with a session; the window controller does that.
    package var onIntent: ((ReaderIntent.Kind) -> Void)?

    package let textView = ReaderTextView.make()

    private let backdrop = BackdropView()
    private let card = CardView()
    private let header = CardHeaderView()
    private let scrollView = NSScrollView()
    private let footerLabel = NSTextField(labelWithString: "")

    private var content = ReaderContent.nothing
    private var chrome = ReaderChrome(fontSize: FontSize(points: 64), mode: .following)
    /// Set when the content or the card size changes; consumed by the next `setCardFrame(_:)`.
    private var needsScroll = true
    private var measured: (width: CGFloat, maxHeight: CGFloat, size: CGSize)?

    package init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Public API

    /// The card's frame in the root view's (non-flipped) coordinates.
    package var cardFrame: CGRect { card.frame }

    package var isBackdropVisible: Bool { !backdrop.isHidden }

    /// Re-renders the chrome; replaces the text only when the content changed, so the selection survives
    /// chrome-only updates (zoom).
    package func render(content: ReaderContent, chrome: ReaderChrome) {
        _ = view
        let contentChanged = content != self.content
        let fontChanged = chrome.fontSize != self.chrome.fontSize
        self.content = content
        self.chrome = chrome
        applyChrome()
        if contentChanged || fontChanged {
            applyContent()
            needsScroll = true
        }
        measured = nil
    }

    /// The card's height for `width`, fitted to the text and capped at `maxHeight` (then the text scrolls).
    package func preferredCardSize(width: CGFloat, maxHeight: CGFloat) -> CGSize {
        _ = view
        if let measured, measured.width == width, measured.maxHeight == maxHeight { return measured.size }
        let chromeHeight = self.chromeHeight
        let textHeight = textContentHeight(width: width - Theme.cardPadding * 2)
        let minimum = chromeHeight + lineHeight
        let height = max(minimum, min(chromeHeight + textHeight, maxHeight)).rounded(.up)
        let size = CGSize(width: width, height: height)
        measured = (width, maxHeight, size)
        return size
    }

    /// Moves and resizes the card (root-view coordinates), then keeps the reading position visible.
    package func setCardFrame(_ frame: CGRect) {
        _ = view
        if card.frame.size != frame.size { needsScroll = true }
        card.frame = frame
        card.layoutSubtreeIfNeeded()
        scrollView.hasVerticalScroller = textView.frame.height > scrollView.contentSize.height + 0.5
        if needsScroll {
            needsScroll = false
            scrollToReadingPosition()
        }
    }

    /// Fades the dimmed backdrop in (pinned) or hides it at once (following).
    package func setBackdropVisible(_ visible: Bool, animated: Bool) {
        _ = view
        guard visible else {
            backdrop.alphaValue = 0
            backdrop.isHidden = true
            return
        }
        backdrop.isHidden = false
        guard animated else {
            backdrop.alphaValue = 1
            return
        }
        backdrop.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.fadeDuration
            backdrop.animator().alphaValue = 1
        }
    }

    // MARK: - View

    override package func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        root.autoresizingMask = [.width, .height]
        root.appearance = NSAppearance(named: .darkAqua)
        view = root

        backdrop.frame = root.bounds
        backdrop.autoresizingMask = [.width, .height]
        backdrop.onClick = { [weak self] in self?.onIntent?(.close(.userCancelled)) }
        root.addSubview(backdrop)
        setBackdropVisible(false, animated: false)

        buildCard(in: root)
        applyChrome()
        applyContent()
    }

    private func buildCard(in container: NSView) {
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.maskImage = Theme.roundedMask(cornerRadius: Theme.cardCornerRadius)
        card.autoresizingMask = []
        container.addSubview(card)

        footerLabel.textColor = Theme.footerColor
        footerLabel.lineBreakMode = .byTruncatingTail
        footerLabel.maximumNumberOfLines = 1
        footerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textView.onAction = { [weak self] action in self?.handle(action) }

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // The scroll view takes whatever height the card leaves after the header and footer.
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [header, scrollView, footerLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = Theme.cardSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let padding = Theme.cardPadding
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),

            header.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footerLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    // MARK: - Rendering

    private var fontSize: CGFloat { CGFloat(chrome.fontSize.points) }

    private func applyChrome() {
        guard isViewLoaded else { return }
        let headerSize = (fontSize * Theme.headerScale).rounded()
        header.render(
            title: ReaderStrings.title(appName: chrome.appName),
            bundleIdentifier: chrome.bundleIdentifier,
            size: headerSize
        )
        footerLabel.font = Theme.footerFont(size: (fontSize * Theme.footerScale).rounded())
        footerLabel.stringValue = ReaderStrings.footer(chrome.mode)
    }

    private func applyContent() {
        guard isViewLoaded else { return }
        switch content {
        case .text(let text, _):
            textView.isSelectable = true
            textView.setText(text, font: Theme.editorFont(size: fontSize), color: Theme.textColor)
        case .hidden:
            textView.isSelectable = false
            textView.setText(ReaderStrings.hiddenText, font: Theme.editorFont(size: fontSize), color: Theme.footerColor)
        case .nothing:
            textView.isSelectable = false
            let size = (fontSize * Theme.readerPlaceholderScale).rounded()
            textView.setText(ReaderStrings.noText, font: Theme.editorFont(size: size), color: Theme.footerColor)
        }
    }

    // MARK: - Measuring

    /// Padding, header, footer and the spacing between them: everything but the text.
    private var chromeHeight: CGFloat {
        Theme.cardPadding * 2 + Theme.cardSpacing * 2 + header.fittingSize.height + footerLabel.fittingSize.height
    }

    private var lineHeight: CGFloat {
        let font = textView.font ?? Theme.editorFont(size: fontSize)
        let line = textView.layoutManager?.defaultLineHeight(for: font) ?? font.pointSize
        return line + textView.textContainerInset.height * 2
    }

    private func textContentHeight(width: CGFloat) -> CGFloat {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return 0 }
        if textView.frame.width != width {
            // The container tracks the text view's width; the scroll view gives it the same width later.
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        }
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
    }

    // MARK: - Scrolling

    /// Centres the line containing `scrollToUTF16`, or shows the top when there is none.
    private func scrollToReadingPosition() {
        let clipView = scrollView.contentView
        guard case .text(let text, let offset?) = content,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              !text.isEmpty
        else {
            clipView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(clipView)
            return
        }
        let length = (text as NSString).length
        let characterIndex = max(0, min(offset, length - 1))
        layoutManager.ensureLayout(for: container)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let lineMidY = line.midY + textView.textContainerOrigin.y
        let maxY = max(0, textView.frame.height - clipView.bounds.height)
        let y = max(0, min(lineMidY - clipView.bounds.height / 2, maxY))
        clipView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: - Actions

    private func handle(_ action: ReaderAction) {
        switch action {
        case .close: onIntent?(.close(.userCancelled))
        case .zoom(let step): onIntent?(.zoom(step))
        case .copy, .selectAll: textView.perform(action)
        }
    }
}
