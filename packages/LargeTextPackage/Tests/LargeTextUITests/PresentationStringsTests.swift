import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("Presentation strings")
struct PresentationStringsTests {
    // MARK: Editor header

    @Test func titleNamesTarget() {
        #expect(EditorStrings.title(targetName: "Safari") == "Typing into Safari")
    }

    @Test func titleIsNeutralWithoutTarget() {
        #expect(EditorStrings.title(targetName: nil) == EditorStrings.neutralTitle)
        #expect(EditorStrings.title(targetName: "") == EditorStrings.neutralTitle)
    }

    @Test func hints() {
        #expect(EditorStrings.hints(TargetHints()) == [])
        #expect(EditorStrings.hints(TargetHints(willCopyToClipboard: true)) == ["Will copy to clipboard"])
    }

    // MARK: HUD

    @Test(arguments: [
        InsertionFallbackReason.permissionMissing, .noEditableTarget, .targetChanged, .modifiersHeld,
    ])
    func copiedNoticeHasReason(_ reason: InsertionFallbackReason) {
        let content = NoticeContent(.copiedToClipboard(reason))
        #expect(content.title == "Copied — press ⌘V")
        #expect(content.subtitle?.isEmpty == false)
    }

    @Test func otherNotices() {
        #expect(NoticeContent(.clipboardReplaced).title == "Inserted — your clipboard now contains this text")
        #expect(NoticeContent(.secureFieldUnsupported).title == "Password fields aren't supported")
        #expect(NoticeContent(.hotkeyUnavailable(.default)).title == "Shortcut ⌃⌥⌘T unavailable")
    }

    @Test func readerNotices() {
        #expect(NoticeContent(.nothingToRead) == NoticeContent(title: "No readable text under the pointer"))
        #expect(NoticeContent(.readerNeedsAccessibility).title == "Allow Accessibility to read text")
        #expect(NoticeContent(.readerNeedsAccessibility).subtitle?.isEmpty == false)
        #expect(NoticeContent(.readerMenuHint(.readerDefault)).title == "Point at text and press ⌃⌥⌘R")
    }

    // MARK: Reader card

    @Test func readerTitleNamesTheApp() {
        #expect(ReaderStrings.title(appName: "Safari") == "Reading from Safari")
        #expect(ReaderStrings.title(appName: nil) == ReaderStrings.neutralTitle)
        #expect(ReaderStrings.title(appName: "") == ReaderStrings.neutralTitle)
    }

    @Test func readerFooterFollowsTheMode() {
        #expect(ReaderStrings.footer(.pinned) == "⎋ Close · ⌘C Copy · ⌘± Size")
        #expect(ReaderStrings.footer(.following) == "Release to close · Tap to pin")
    }
}
