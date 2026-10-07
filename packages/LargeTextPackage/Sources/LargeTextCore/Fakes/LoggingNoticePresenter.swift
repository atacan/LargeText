import Foundation
import os

@MainActor
package final class LoggingNoticePresenter: NoticePresenting {
    package init() {}

    package func show(_ notice: Notice) {
        Logger.core.info("Notice: \(String(describing: notice))")
    }
}
