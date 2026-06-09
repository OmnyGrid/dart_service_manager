import 'dart:async';
import 'dart:io';

/// A scheduler service that fires on a configurable interval.
///
/// Reads `--interval <seconds>` (default 60) and the `LOG_LEVEL` environment
/// variable, both of which `dart_services:` supplies from the manifest.
Future<void> main(List<String> args) async {
  final interval = _intervalSeconds(args);
  final logLevel = Platform.environment['LOG_LEVEL'] ?? 'info';
  stdout.writeln('scheduler: starting (interval ${interval}s, log $logLevel)');
  ProcessSignal.sigterm.watch().listen((_) => exit(0));

  Timer.periodic(Duration(seconds: interval), (_) {
    stdout.writeln('scheduler: running scheduled job');
  });
}

int _intervalSeconds(List<String> args) {
  final i = args.indexOf('--interval');
  if (i >= 0 && i + 1 < args.length) {
    return int.tryParse(args[i + 1]) ?? 60;
  }
  return 60;
}
