import 'package:dart_service_manager/dart_service_manager.dart';

/// A recorded invocation of [FakeProcessRunner.run].
class RecordedRun {
  /// The executable that was requested.
  final String executable;

  /// The arguments passed to the executable.
  final List<String> args;

  /// The working directory, if any.
  final String? workingDirectory;

  /// The supplemental environment, if any.
  final Map<String, String>? environment;

  RecordedRun(
    this.executable,
    this.args,
    this.workingDirectory,
    this.environment,
  );

  /// The full command line, joined for convenient assertions.
  String get commandLine => '$executable ${args.join(' ')}';

  @override
  String toString() => commandLine;
}

/// A [ProcessRunner] that records every invocation and returns scripted
/// results, so drivers and the compiler can be unit-tested without spawning
/// real processes.
class FakeProcessRunner implements ProcessRunner {
  /// Every invocation, in order.
  final List<RecordedRun> runs = [];

  /// Optional per-executable responder; receives the recorded run and returns
  /// the result to hand back. When `null`, [defaultResult] is used.
  final ProcessRunResult Function(RecordedRun run)? responder;

  /// The result returned when [responder] is `null` or returns `null`.
  final ProcessRunResult defaultResult;

  FakeProcessRunner({
    this.responder,
    this.defaultResult = const ProcessRunResult(exitCode: 0),
  });

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final record = RecordedRun(executable, args, workingDirectory, environment);
    runs.add(record);
    return responder?.call(record) ?? defaultResult;
  }

  /// The most recent invocation.
  RecordedRun get last => runs.last;
}
