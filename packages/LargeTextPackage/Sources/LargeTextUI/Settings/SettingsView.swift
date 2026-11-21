import LargeTextCore
import SwiftUI

/// The Settings window's content (Settings plan §2): a grouped `Form` that renders `SettingsViewModel.state`
/// and sends a `SettingsIntent` for every change. Each shortcut has a recorder (`ShortcutRecorderView`), Reset
/// and, for the reader, Turn Off. Launch at login shows only when `SettingsState.loginItem` isn't `nil`.
package struct SettingsView: View {
    private let model: SettingsViewModel
    @State private var isConfirmingReset = false

    package init(model: SettingsViewModel) {
        self.model = model
    }

    private var state: SettingsState { model.state }

    package var body: some View {
        Form {
            if let scenario = state.context.scenarioName {
                Section {
                    Label(SettingsStrings.scenarioBanner(scenario), systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            shortcutsSection
            textSizeSection
            readerSection
            clipboardSection
            accessibilitySection
            if let status = state.loginItem {
                startupSection(status)
            }
            if let automatic = state.automaticallyChecksForUpdates {
                updatesSection(automatic)
            }
            Section {
                HStack {
                    Spacer()
                    Button(SettingsStrings.resetAll) { isConfirmingReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 360, idealHeight: 680)
        .confirmationDialog(SettingsStrings.resetAllConfirmTitle, isPresented: $isConfirmingReset) {
            Button(SettingsStrings.resetAllConfirmButton, role: .destructive) { model.send(.resetAll) }
            Button(SettingsStrings.cancel, role: .cancel) {}
        } message: {
            Text(SettingsStrings.resetAllConfirmMessage)
        }
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        Section {
            shortcutRow(.editor, key: .hotkey)
            shortcutRow(.reader, key: .readerHotkey)
        } header: {
            Text(SettingsStrings.shortcutsSection)
        } footer: {
            footnote(SettingsStrings.shortcutsFootnote)
        }
    }

    private func shortcutRow(_ slot: ShortcutSlot, key: LargeTextCore.PreferenceKey) -> some View {
        let shortcut = state[slot]
        let model = model
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent(SettingsStrings.shortcutTitle(slot)) {
                HStack(spacing: 8) {
                    ShortcutRecorderRepresentable(slot: slot, shortcut: shortcut) { model.send($0) }
                        .fixedSize()
                    Button(SettingsStrings.reset) { model.send(.resetShortcut(slot)) }
                        .disabled(shortcut.combo == slot.defaultCombo && shortcut.isRegistered && shortcut.problem == nil)
                    if slot == .reader {
                        Button(SettingsStrings.turnOff) { model.send(.turnOffReader) }
                            .disabled(shortcut.combo == nil)
                    }
                }
            }
            if shortcut.isRecording {
                footnote(SettingsStrings.recordingHint)
            } else if let problem = shortcut.problem {
                warning(SettingsStrings.problem(problem))
            } else if shortcut.combo != nil, !shortcut.isRegistered {
                warning(SettingsStrings.notRegistered)
            }
            overrideNote(key)
        }
    }

    // MARK: - Text size

    private var textSizeSection: some View {
        Section {
            fontSizeRow(
                SettingsStrings.editorFontSize,
                size: state.editorFontSize,
                key: .fontSize,
                set: { .setEditorFontSize($0) }
            )
            fontSizeRow(
                SettingsStrings.readerFontSize,
                size: state.readerFontSize,
                key: .readerFontSize,
                set: { .setReaderFontSize($0) }
            )
        } header: {
            Text(SettingsStrings.textSizeSection)
        } footer: {
            footnote(SettingsStrings.fontSizeFootnote)
        }
    }

    private func fontSizeRow(
        _ title: String,
        size: FontSize,
        key: LargeTextCore.PreferenceKey,
        set: @escaping (FontSize) -> SettingsIntent
    ) -> some View {
        let model = model
        let value = Binding(
            get: { size.points },
            set: { model.send(set(FontSize(points: $0))) }
        )
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack {
                    Slider(value: value, in: FontSizePolicy.range, step: FontSizePolicy.step)
                        .labelsHidden()
                        .accessibilityLabel(title)
                    valueLabel(SettingsStrings.fontSize(size))
                }
            }
            overrideNote(key)
        }
    }

    // MARK: - Reader

    private var readerSection: some View {
        let model = model
        let threshold = Binding(
            get: { model.holdThresholdMilliseconds },
            set: { model.setHoldThreshold(milliseconds: $0) }
        )
        let following = Binding(
            get: { model.state.followingUnit },
            set: { model.send(.setFollowingUnit($0)) }
        )
        let pinned = Binding(
            get: { model.state.pinnedUnit },
            set: { model.send(.setPinnedUnit($0)) }
        )
        return Section {
            Group {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(SettingsStrings.holdThreshold) {
                        HStack {
                            Slider(
                                value: threshold,
                                in: SettingsViewModel.holdThresholdRange,
                                step: SettingsViewModel.holdThresholdStep
                            )
                            .labelsHidden()
                            .accessibilityLabel(SettingsStrings.holdThreshold)
                            valueLabel(SettingsStrings.milliseconds(Int(model.holdThresholdMilliseconds)))
                        }
                    }
                    overrideNote(.readerHoldThreshold)
                }
                VStack(alignment: .leading, spacing: 4) {
                    unitPicker(SettingsStrings.followingUnit, selection: following)
                    overrideNote(.followingUnit)
                }
                VStack(alignment: .leading, spacing: 4) {
                    unitPicker(SettingsStrings.pinnedUnit, selection: pinned)
                    overrideNote(.pinnedUnit)
                }
            }
            .disabled(!state.isReaderOn)
        } header: {
            Text(SettingsStrings.readerSection)
        } footer: {
            if !state.isReaderOn {
                footnote(SettingsStrings.readerOffFootnote)
            }
        }
    }

    private func unitPicker(_ title: String, selection: Binding<ReadGranularity>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ReadGranularity.allCases, id: \.self) { unit in
                Text(SettingsStrings.unit(unit)).tag(unit)
            }
        }
    }

    // MARK: - Clipboard

    private var clipboardSection: some View {
        let model = model
        let restores = Binding(
            get: { model.state.restoresClipboard },
            set: { model.send(.setRestoresClipboard($0)) }
        )
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsStrings.restoresClipboard, isOn: restores)
                overrideNote(.clipboardRestore)
            }
        } header: {
            Text(SettingsStrings.clipboardSection)
        } footer: {
            footnote(SettingsStrings.clipboardFootnote)
        }
    }

    // MARK: - Accessibility

    private var accessibilitySection: some View {
        let setup = state.permission
        return Section {
            LabeledContent(SettingsStrings.accessibilityTitle) {
                HStack(spacing: 8) {
                    Text(SettingsStrings.permissionStatus(setup))
                        .foregroundStyle(setup == .granted ? .secondary : .primary)
                    switch setup {
                    case .granted:
                        EmptyView()
                    case .needsGrant:
                        Button(SettingsStrings.grantAccess) { model.send(.grantAccess) }
                    case .needsRelaunch:
                        Button(SettingsStrings.relaunch) { model.send(.relaunch) }
                    }
                }
            }
        } header: {
            Text(SettingsStrings.accessibilitySection)
        } footer: {
            if let note = SettingsStrings.permissionFootnote(setup) {
                footnote(note)
            }
        }
    }

    // MARK: - Launch at login

    private func startupSection(_ status: LoginItemStatus) -> some View {
        let model = model
        let isOn = Binding(
            get: { status.isOn },
            set: { model.send(.setLaunchAtLogin($0)) }
        )
        let error = state.loginItemError
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsStrings.launchAtLogin, isOn: isOn)
                if let error {
                    warning(SettingsStrings.loginItemError(error))
                } else if let note = SettingsStrings.loginItemNote(status) {
                    footnote(note)
                }
                if SettingsStrings.showsOpenLoginItems(status: status, error: error) {
                    Button(SettingsStrings.openLoginItems) { model.send(.openLoginItemsSettings) }
                }
            }
        } header: {
            Text(SettingsStrings.startupSection)
        }
    }

    // MARK: - Updates

    private func updatesSection(_ automatic: Bool) -> some View {
        let model = model
        let isOn = Binding(
            get: { automatic },
            set: { model.send(.setAutomaticallyChecksForUpdates($0)) }
        )
        return Section {
            LabeledContent {
                Button(SettingsStrings.checkForUpdatesNow) { model.send(.checkForUpdates) }
                    .disabled(!state.canCheckForUpdates)
            } label: {
                Toggle(SettingsStrings.automaticallyChecksForUpdates, isOn: isOn)
            }
        } header: {
            Text(SettingsStrings.updatesSection)
        } footer: {
            footnote(SettingsStrings.updatesFootnote)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func overrideNote(_ key: LargeTextCore.PreferenceKey) -> some View {
        if state.context.isOverridden(key) {
            Label(SettingsStrings.overrideNote(key), systemImage: "terminal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valueLabel(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 56, alignment: .trailing)
    }
}
