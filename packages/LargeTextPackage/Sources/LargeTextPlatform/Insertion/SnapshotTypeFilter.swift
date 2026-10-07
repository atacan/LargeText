/// Decides which pasteboard types a snapshot copies (§2.5 step 5).
///
/// Skipped:
/// - `dyn.*` — dynamic UTIs that the system synthesizes from other types;
/// - file-promise types — reading them can force the source app to produce (large) files.
///
/// The nspasteboard.org marker types (`org.nspasteboard.ConcealedType`, `TransientType`, …) are kept on
/// purpose: restoring a concealed password without its marker would leak it into clipboard managers.
package enum SnapshotTypeFilter {
    static let skippedTypes: Set<String> = [
        "com.apple.NSFilePromiseItemMetaData",
        "com.apple.pasteboard.promised-file-url",
        "com.apple.pasteboard.promised-file-content-type",
        "com.apple.pasteboard.promised-suggested-file-name",
        "NSPromiseContentsPboardType",
        "Apple files promise pasteboard type",
    ]

    package static func shouldInclude(_ type: String) -> Bool {
        !type.hasPrefix("dyn.") && !skippedTypes.contains(type)
    }
}
