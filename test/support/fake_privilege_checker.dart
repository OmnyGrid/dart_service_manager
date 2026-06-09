import 'package:dart_service_manager/dart_service_manager.dart';

/// A [PrivilegeChecker] that returns a fixed, configurable elevation state.
class FakePrivilegeChecker implements PrivilegeChecker {
  /// Whether [isElevated] reports the process as elevated.
  bool elevated;

  FakePrivilegeChecker({this.elevated = false});

  @override
  Future<bool> isElevated() async => elevated;
}

/// A [ServiceLogger] that records every message, for asserting on emitted
/// warnings in tests.
class RecordingServiceLogger implements ServiceLogger {
  /// `LEVEL: message` lines, in order.
  final List<String> records = [];

  /// All recorded messages joined, for convenient `contains` assertions.
  String get text => records.join('\n');

  @override
  bool isEnabled(LogLevel level) => true;

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    records.add('${level.name}: $message');
  }
}
