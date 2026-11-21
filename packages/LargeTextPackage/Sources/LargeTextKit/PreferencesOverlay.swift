import LargeTextCore

/// The reader tunables from the launch arguments, laid over the real store (§5.4). An overridden key lives in
/// memory only and is never written through, so trying a value never changes `UserDefaults`; every other key
/// reads and writes the base store.
@MainActor
final class PreferencesOverlay: PreferencesStore {
    private let base: any PreferencesStore
    private var readerHoldThresholdOverride: Duration?
    private var followingUnitOverride: ReadGranularity?

    init(base: any PreferencesStore, readerHoldThreshold: Duration?, followingUnit: ReadGranularity?) {
        self.base = base
        readerHoldThresholdOverride = readerHoldThreshold
        followingUnitOverride = followingUnit
    }

    var readerHoldThreshold: Duration {
        get { readerHoldThresholdOverride ?? base.readerHoldThreshold }
        set {
            if readerHoldThresholdOverride != nil {
                readerHoldThresholdOverride = newValue
            } else {
                base.readerHoldThreshold = newValue
            }
        }
    }

    var followingUnit: ReadGranularity {
        get { followingUnitOverride ?? base.followingUnit }
        set {
            if followingUnitOverride != nil {
                followingUnitOverride = newValue
            } else {
                base.followingUnit = newValue
            }
        }
    }

    var fontSize: FontSize {
        get { base.fontSize }
        set { base.fontSize = newValue }
    }

    var hotkey: KeyCombo {
        get { base.hotkey }
        set { base.hotkey = newValue }
    }

    var clipboardRestore: ClipboardRestorePolicy {
        get { base.clipboardRestore }
        set { base.clipboardRestore = newValue }
    }

    var readerHotkey: KeyCombo? {
        get { base.readerHotkey }
        set { base.readerHotkey = newValue }
    }

    var readerFontSize: FontSize {
        get { base.readerFontSize }
        set { base.readerFontSize = newValue }
    }

    var pinnedUnit: ReadGranularity {
        get { base.pinnedUnit }
        set { base.pinnedUnit = newValue }
    }

    var hasCompletedFirstLaunch: Bool {
        get { base.hasCompletedFirstLaunch }
        set { base.hasCompletedFirstLaunch = newValue }
    }
}
