import Foundation

package struct InstantSleeper: Sleeper {
    package init() {}
    package func sleep(for duration: Duration) async throws {}
}
