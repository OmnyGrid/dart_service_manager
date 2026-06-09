import 'dart:io';

import 'package:dart_service_manager/dart_service_manager_cli.dart';

/// Entry point for the `dart-service` command-line interface.
///
/// All behaviour lives in the library (`runCli`); this wrapper only forwards
/// arguments and propagates the resulting process exit code.
Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
