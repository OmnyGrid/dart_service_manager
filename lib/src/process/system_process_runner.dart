import 'dart:io';

import 'process_runner.dart';

/// The production [ProcessRunner] that executes real OS processes via
/// `dart:io`'s [Process.run].
///
/// This is a thin pass-through with no logic of its own, so it is excluded from
/// the unit-test coverage target; behaviour is validated indirectly by the
/// platform-tagged integration tests.
final class SystemProcessRunner implements ProcessRunner {
  /// Creates a system process runner.
  const SystemProcessRunner();

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    return ProcessRunResult(
      exitCode: result.exitCode,
      stdout: result.stdout is String
          ? result.stdout as String
          : String.fromCharCodes(result.stdout as List<int>),
      stderr: result.stderr is String
          ? result.stderr as String
          : String.fromCharCodes(result.stderr as List<int>),
    );
  }
}
