import Foundation

/// Convenience wrapper around `NeoLogger.shared` that lets you log from
/// synchronous code without manual `Task {}` wrapping at every call site.
///
/// Calls return immediately; they dispatch the log into the actor asynchronously.
public enum NeoLog {
  @inlinable
  public static func log(
    _ domain: Domain,
    _ level: Level,
    _ message: @autoclosure @escaping @Sendable () -> String,
    file: String = #fileID,
    line: Int = #line,
    function: String = #function
  ) {
    let text = message()
    Task.detached(priority: .utility) {
      await NeoLogger.shared.log(domain, level, text, file: file, line: line, function: function)
    }
  }

  @inlinable
  public static func log(
    _ domain: Domain,
    _ level: Level,
    _ data: Data,
    file: String = #fileID,
    line: Int = #line,
    function: String = #function
  ) {
    Task.detached(priority: .utility) {
      await NeoLogger.shared.log(domain, level, data, file: file, line: line, function: function)
    }
  }

  @inlinable
  public static func mark(_ text: String = "Mark") {
    Task.detached(priority: .utility) {
      await NeoLogger.shared.mark(text)
    }
  }

  // MARK: Severity shortcuts

  @inlinable public static func error(
    _ domain: Domain = .app, _ m: @autoclosure @escaping @Sendable () -> String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .error, m(), file: file, line: line, function: function) }

  @inlinable public static func warning(
    _ domain: Domain = .app, _ m: @autoclosure @escaping @Sendable () -> String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .warning, m(), file: file, line: line, function: function) }

  @inlinable public static func info(
    _ domain: Domain = .app, _ m: @autoclosure @escaping @Sendable () -> String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .info, m(), file: file, line: line, function: function) }

  @inlinable public static func debug(
    _ domain: Domain = .app, _ m: @autoclosure @escaping @Sendable () -> String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .debug, m(), file: file, line: line, function: function) }

  @inlinable public static func verbose(
    _ domain: Domain = .app, _ m: @autoclosure @escaping @Sendable () -> String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .verbose, m(), file: file, line: line, function: function) }
}
