import Foundation
import LargeTextCore

/// String form of `ClipboardRestorePolicy` stored under `LargeText.clipboardRestore`.
///
/// | Stored string        | Policy                                         |
/// |----------------------|------------------------------------------------|
/// | `none`               | `.none` (no snapshot, no restore)              |
/// | `restore`            | `.default` (`.restore(maxBytes: 10 MB)`)       |
/// | `restore:<bytes>`    | `.restore(maxBytes: <bytes>)`, bytes > 0       |
///
/// Matching is case-insensitive and ignores surrounding whitespace, so
/// `defaults write <bundle id> LargeText.clipboardRestore none` works as documented in §2.5.
extension ClipboardRestorePolicy {
    package init?(defaultsString: String) {
        let value = defaultsString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "none":
            self = .none
        case "restore":
            self = .default
        default:
            let prefix = "restore:"
            guard value.hasPrefix(prefix),
                  let bytes = Int(value.dropFirst(prefix.count)),
                  bytes > 0 else { return nil }
            self = .restore(maxBytes: bytes)
        }
    }

    package var defaultsString: String {
        switch self {
        case .none: "none"
        case .restore(let maxBytes): "restore:\(maxBytes)"
        }
    }
}
