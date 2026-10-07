import Foundation

package protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}
