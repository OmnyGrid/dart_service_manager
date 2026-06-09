import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../errors/service_exception.dart';
import '../logging/log_level.dart';
import '../logging/service_logger.dart';
import '../manager/dart_service_manager.dart';
import '../models/service_scope.dart';
import 'commands.dart';

/// Builds a `DartServiceManager` for a CLI invocation, honouring `--verbose`.
typedef ManagerFactory = DartServiceManager Function({required bool verbose});

/// Assembles the `dart-service` [CommandRunner].
///
/// [managerFactory] supplies the [DartServiceManager] each command runs
/// against; the default builds one wired for the current platform, while tests
/// inject a manager backed by fakes. [out] receives all human-readable output.
CommandRunner<int> buildServiceRunner({
  ManagerFactory? managerFactory,
  StringSink? out,
}) {
  final sink = out ?? stdout;
  final factory = managerFactory ?? _defaultManagerFactory;
  final runner =
      CommandRunner<int>(
          'dart-service',
          'Declare, compile, install and manage Dart-package services as '
              'native OS services.',
        )
        ..argParser.addOption(
          'scope',
          allowed: ['user', 'system'],
          defaultsTo: 'user',
          help: 'Privilege scope to install services under.',
        )
        ..argParser.addOption(
          'path',
          help:
              'Explicit path to the package directory (overrides name '
              'resolution).',
        )
        ..argParser.addFlag(
          'verbose',
          abbr: 'v',
          negatable: false,
          help: 'Enable debug logging.',
        );

  for (final command in [
    InstallCommand(factory, sink),
    UninstallCommand(factory, sink),
    StartCommand(factory, sink),
    StopCommand(factory, sink),
    PauseCommand(factory, sink),
    ResumeCommand(factory, sink),
    RestartCommand(factory, sink),
    StatusCommand(factory, sink),
    ListCommand(factory, sink),
    PackagesCommand(factory, sink),
    ServicesCommand(factory, sink),
  ]) {
    runner.addCommand(command);
  }
  return runner;
}

/// Runs the `dart-service` CLI with [args] and returns a process exit code.
///
/// Usage errors map to exit code 64; [ServiceManagerException]s print
/// `error: <message>` to [errOut] and map to exit code 1.
Future<int> runCli(
  List<String> args, {
  ManagerFactory? managerFactory,
  StringSink? out,
  StringSink? errOut,
}) async {
  final err = errOut ?? stderr;
  try {
    final code = await buildServiceRunner(
      managerFactory: managerFactory,
      out: out,
    ).run(args);
    return code ?? 0;
  } on UsageException catch (e) {
    err.writeln(e);
    return 64;
  } on ServiceManagerException catch (e) {
    err.writeln('error: ${e.message}');
    return 1;
  }
}

DartServiceManager _defaultManagerFactory({required bool verbose}) =>
    DartServiceManager.forCurrentPlatform(
      logger: verbose
          ? ConsoleServiceLogger(minLevel: LogLevel.debug)
          : const SilentServiceLogger(),
    );

/// Reads the `--scope` global option as a [ServiceScope].
ServiceScope scopeFromGlobals(ArgResults? globals) =>
    ServiceScope.tryParse(globals?['scope'] as String? ?? 'user') ??
    ServiceScope.user;
