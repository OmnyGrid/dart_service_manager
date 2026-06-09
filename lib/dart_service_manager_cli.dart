/// The `dart-service` command-line interface, exposed as a library so it can be
/// embedded and unit-tested.
///
/// [buildServiceRunner] assembles the `CommandRunner`; [runCli] is the entry
/// point used by `bin/dart_service.dart`.
library;

export 'src/cli/cli_runner.dart';
