import 'dart:async';
import 'dart:io';

/// A monitor service that periodically samples system load.
Future<void> main(List<String> args) async {
  stdout.writeln('monitor: starting (pid $pid)');
  ProcessSignal.sigterm.watch().listen((_) => exit(0));

  Timer.periodic(const Duration(seconds: 10), (_) {
    stdout.writeln('monitor: sampling metrics');
  });
}
