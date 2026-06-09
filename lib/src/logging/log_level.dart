/// Severity levels for [ServiceLogger](service_logger.dart) messages, ordered
/// from most to least verbose.
///
/// A logger configured at a given level emits that level and everything more
/// severe; see [ServiceLogger.isEnabled].
enum LogLevel {
  /// Fine-grained diagnostic detail useful when debugging.
  debug,

  /// Normal lifecycle progress (installed, started, stopped, …).
  info,

  /// A recoverable problem or an unexpected-but-handled condition.
  warning,

  /// A failure that aborted the requested operation.
  error;

  /// The relative ordering used to filter messages; higher is more severe.
  int get severity => index;
}
