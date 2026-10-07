import AppKit

/// The card's header row: the target app's icon and a one-line title. Shared by the editor and the reader.
@MainActor
final class CardHeaderView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var iconWidth: NSLayoutConstraint?
    private var iconHeight: NSLayoutConstraint?
    /// Outer optional: "not resolved yet"; inner: the bundle id the current icon belongs to.
    private var iconBundleIdentifier: String??

    var title: String { titleLabel.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// - Parameter size: the header font size; the icon scales with it.
    func render(title: String, bundleIdentifier: String?, size: CGFloat) {
        titleLabel.font = Theme.headerFont(size: size)
        titleLabel.stringValue = title
        updateIcon(bundleIdentifier: bundleIdentifier)
        let iconEdge = (size * Theme.iconScale).rounded()
        iconWidth?.constant = iconEdge
        iconHeight?.constant = iconEdge
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.textColor = Theme.headerColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [iconView, titleLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let iconWidth = iconView.widthAnchor.constraint(equalToConstant: 32)
        let iconHeight = iconView.heightAnchor.constraint(equalToConstant: 32)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconWidth,
            iconHeight,
        ])
        self.iconWidth = iconWidth
        self.iconHeight = iconHeight
    }

    private func updateIcon(bundleIdentifier: String?) {
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
}
