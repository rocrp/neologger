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

extension Message {
  var text: String? {
    for part in parts where part.key == PartKey.message.rawValue {
      if case .string(let s) = part.value { return s }
    }
    return nil
  }

  var seq: Int32? {
    for part in parts where part.key == PartKey.messageSeq.rawValue {
      if case .int32(let v) = part.value { return v }
    }
    return nil
  }

  var isClientInfo: Bool {
    for part in parts where part.key == PartKey.messageType.rawValue {
      if case .int32(let v) = part.value { return v == MessageType.clientInfo.rawValue }
    }
    return false
  }
}

actor Flag {
  private(set) var value = false
  func set() { value = true }
}

/// Wraps a continuation so racing callbacks can only resume it once.
final class ResumeOnce<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?

  init(_ continuation: CheckedContinuation<T, Error>) {
    self.continuation = continuation
  }

  func resume(returning value: T) {
    take()?.resume(returning: value)
  }

  func resume(throwing error: Error) {
    take()?.resume(throwing: error)
  }

  private func take() -> CheckedContinuation<T, Error>? {
    lock.lock()
    defer { lock.unlock() }
    let taken = continuation
    continuation = nil
    return taken
  }
}
