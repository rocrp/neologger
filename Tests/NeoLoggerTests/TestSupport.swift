import Foundation
import NeoLogger
import Testing

struct TimedOut: Error {}

/// Polls `condition` until it returns true or `timeout` elapses.
func eventually(
  timeout: Duration = .seconds(5),
  interval: Duration = .milliseconds(25),
  _ condition: () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if try await condition() { return }
    try await Task.sleep(for: interval)
  }
  throw TimedOut()
}

actor Flag {
  private(set) var value = false
  func set() { value = true }
}

/// Collects `NWMessageListener` events for assertions.
actor ListenerEvents {
  private var store: [Int: [Message]] = [:]
  private var connected: [Int] = []

  func record(_ event: NWMessageListener.Event) {
    switch event.kind {
    case .connected:
      connected.append(event.connection)
      store[event.connection] = []
    case .message(let message):
      store[event.connection, default: []].append(message)
    case .disconnected:
      break
    }
  }

  var connectionCount: Int { connected.count }

  func messages(on id: Int) -> [Message] { store[id] ?? [] }
}

/// Starts consuming the listener's event stream into a `ListenerEvents` log.
func observe(_ listener: NWMessageListener) -> ListenerEvents {
  let events = ListenerEvents()
  Task {
    for await event in listener.events {
      await events.record(event)
    }
  }
  return events
}
