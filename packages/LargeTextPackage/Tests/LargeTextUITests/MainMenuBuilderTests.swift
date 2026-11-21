import AppKit
import Testing
@testable import LargeTextUI

/// The menu is built but never installed, so the test process's `NSApp.mainMenu` is left alone.
@MainActor
@Suite("MainMenuBuilder")
struct MainMenuBuilderTests {
    private struct Entry: Equatable {
        var title: String
        var key: String
        var modifiers: NSEvent.ModifierFlags

        init(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) {
            self.title = title
            self.key = key
            self.modifiers = key.isEmpty ? [] : modifiers
        }

        init(_ item: NSMenuItem) {
            self.init(item.isSeparatorItem ? "-" : item.title, item.keyEquivalent, item.keyEquivalentModifierMask)
        }
    }

    private func entries(_ menu: NSMenu?) -> [Entry] {
        (menu?.items ?? []).map(Entry.init)
    }

    private func makeBuilder(
        allowsAppCommands: @escaping @MainActor () -> Bool = { true },
        onOpenSettings: @escaping @MainActor () -> Void = {}
    ) -> MainMenuBuilder {
        _ = NSApplication.shared
        return MainMenuBuilder(onOpenSettings: onOpenSettings, allowsAppCommands: allowsAppCommands)
    }

    @Test func topLevelMenus() {
        let menu = makeBuilder().makeMenu()
        #expect(menu.items.map(\.title) == ["LargeText", "Edit", "Window"])
        #expect(menu.items.allSatisfy { $0.submenu != nil })
    }

    @Test func appMenuItemsAndKeyEquivalents() {
        let app = makeBuilder().makeMenu().items[0].submenu
        #expect(entries(app) == [
            Entry("About LargeText"),
            Entry("-"),
            Entry("Settings…", ","),
            Entry("-"),
            Entry("Hide LargeText", "h"),
            Entry("-"),
            Entry("Quit LargeText", "q"),
        ])
    }

    @Test func editMenuUsesTheStandardSelectorsThroughTheResponderChain() throws {
        let edit = try #require(makeBuilder().makeMenu().items[1].submenu)
        #expect(entries(edit) == [
            Entry("Undo", "z"),
            Entry("Redo", "z", [.command, .shift]),
            Entry("-"),
            Entry("Cut", "x"),
            Entry("Copy", "c"),
            Entry("Paste", "v"),
            Entry("Select All", "a"),
        ])
        let actions = edit.items.filter { !$0.isSeparatorItem }.map { $0.action.map(NSStringFromSelector) }
        #expect(actions == ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:"])
        #expect(edit.items.allSatisfy { $0.target == nil })
    }

    @Test func windowMenu() throws {
        let window = try #require(makeBuilder().makeMenu().items[2].submenu)
        #expect(entries(window) == [Entry("Minimize", "m"), Entry("Close", "w")])
        #expect(window.items.map { $0.action.map(NSStringFromSelector) } == ["performMiniaturize:", "performClose:"])
    }

    @Test func settingsItemCallsOnOpenSettings() throws {
        var opened = 0
        let builder = makeBuilder(onOpenSettings: { opened += 1 })
        let settings = try #require(builder.makeMenu().items[0].submenu?.items.first { $0.title == "Settings…" })

        let action = try #require(settings.action)
        _ = (settings.target as? NSObject)?.perform(action, with: settings)

        #expect(opened == 1)
    }

    /// With a panel key, an unhandled ⌘Q or ⌘H in the editor must do nothing.
    @Test(arguments: [false, true])
    func appCommandsFollowTheValidationRule(_ allows: Bool) throws {
        let builder = makeBuilder(allowsAppCommands: { allows })
        let app = try #require(builder.makeMenu().items[0].submenu)
        let commands = app.items.filter { !$0.isSeparatorItem }

        #expect(commands.count == 4)
        #expect(commands.allSatisfy { $0.target === builder })
        #expect(commands.allSatisfy { builder.validateMenuItem($0) == allows })
    }
}
