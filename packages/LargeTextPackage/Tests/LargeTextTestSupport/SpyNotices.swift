import Foundation
import LargeTextCore

@MainActor
package final class SpyNotices: NoticePresenting {
    package private(set) var shown: [Notice] = []
    private let log: EventLog?

    package init(log: EventLog? = nil) {
        self.log = log
    }

    package func show(_ notice: Notice) {
        shown.append(notice)
        log?.append(.notice(notice))
    }
}
