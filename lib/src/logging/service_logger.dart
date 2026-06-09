import 'dart:io';

import 'log_level.dart';

/// Sink for structured diagnostic messages emitted by the service manager.
///
/// Consumers inject their own implementation to route logs into an existing
/// logging framework. Two implementations ship with the package:
/// [SilentServiceLogger] (the default — discards everything) and
/// [ConsoleServiceLogger] (writes to stdout/stderr).
///
/// ```dart
/// final manager = DartServiceManager(logger: ConsoleServiceLogger());
/// ```
abstract interface class ServiceLogger {
  /// Records [message] at the given [level], optionally attaching the [error]
  /// and [stackTrace] that prompted it.
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  });

  /// Whether messages at [level] would be emitted; lets callers skip building
  /// expensive messages that would be discarded.
  bool isEnabled(LogLevel level);
}

/// Convenience level-specific helpers shared by all [ServiceLogger]s.
extension ServiceLoggerHelpers on ServiceLogger {
  /// Logs at [LogLevel.debug].
  void debug(String message) => log(LogLevel.debug, message);

  /// Logs at [LogLevel.info].
  void info(String message) => log(LogLevel.info, message);

  /// Logs at [LogLevel.warning].
  void warning(String message, {Object? error}) =>
      log(LogLevel.warning, message, error: error);

  /// Logs at [LogLevel.error].
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.error, message, error: error, stackTrace: stackTrace);
}

/// A [ServiceLogger] that discards every message. This is the default so the
/// library is silent unless a consumer opts in to logging.
final class SilentServiceLogger implements ServiceLogger {
  /// Creates a silent logger.
  const SilentServiceLogger();

  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// A [ServiceLogger] that writes human-readable lines to the console: `error`
/// and `warning` go to stderr, everything else to stdout.
///
/// Messages below [minLevel] are dropped.
final class ConsoleServiceLogger implements ServiceLogger {
  /// The lowest level that will be emitted; defaults to [LogLevel.info].
  final LogLevel minLevel;

  /// The sink for stdout-bound lines (overridable for testing).
  final StringSink _out;

  /// The sink for stderr-bound lines (overridable for testing).
  final StringSink _err;

  /// Creates a console logger emitting [minLevel] and above.
  ///
  /// [out] and [err] default to `stdout` and `stderr`; pass `StringBuffer`s (or
  /// any [StringSink]) to capture output in tests.
  ConsoleServiceLogger({
    this.minLevel = LogLevel.info,
    StringSink? out,
    StringSink? err,
  }) : _out = out ?? stdout,
       _err = err ?? stderr;

  @override
  bool isEnabled(LogLevel level) => level.severity >= minLevel.severity;

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isEnabled(level)) return;
    final label = level.name.toUpperCase();
    final buffer = StringBuffer('[$label] $message');
    if (error != null) buffer.write(' (error: $error)');
    final sink = level == LogLevel.error || level == LogLevel.warning
        ? _err
        : _out;
    sink.writeln(buffer);
    if (stackTrace != null && level == LogLevel.error) {
      _err.writeln(stackTrace);
    }
  }
}
