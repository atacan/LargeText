import Foundation

/// One shared, ordered record of side effects across ports, so tests can assert cross-port ordering.
@MainActor
package final class EventLog {
    package private(set) var events: [RecordedEvent] = []

    package init() {}

    package func append(_ event: RecordedEvent) {
        events.append(event)
    }

    package func removeAll() {
        events.removeAll()
    }
}
