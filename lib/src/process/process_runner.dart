/// The outcome of running an external process.
///
/// A small, immutable view over `dart:io`'s `ProcessResult` that keeps the
/// abstraction free of platform types so it is trivial to fake in tests.
class ProcessRunResult {
  /// The process exit code; `0` conventionally means success.
  final int exitCode;

  /// The captured standard output, decoded as a string.
  final String stdout;

  /// The captured standard error, decoded as a string.
  final String stderr;

  /// Creates a process result.
  const ProcessRunResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  /// Whether the process exited successfully (exit code `0`).
  bool get succeeded => exitCode == 0;

  @override
  String toString() => 'ProcessRunResult(exit: $exitCode)';
}

/// Abstraction over launching external processes (`systemctl`, `launchctl`,
/// `sc.exe`, `dart compile`, …).
///
/// Funnelling every process call through this interface keeps the drivers and
/// compiler fully unit-testable: tests inject a fake that records invocations
/// and returns canned [ProcessRunResult]s, while production wires
/// [SystemProcessRunner](system_process_runner.dart).
abstract interface class ProcessRunner {
  /// Runs [executable] with [args], awaiting completion.
  ///
  /// [workingDirectory] sets the child's working directory; [environment] adds
  /// to (or overrides) the inherited environment. The captured stdout/stderr
  /// and exit code are returned — a non-zero exit code is *not* itself an
  /// error, callers decide how to interpret it.
  Future<ProcessRunResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}
