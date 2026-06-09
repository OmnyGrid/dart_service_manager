import 'dart:async';
import 'dart:io';

/// A trivial long-running worker service.
///
/// Real services do useful work here; this one just logs a heartbeat every few
/// seconds and exits cleanly on SIGTERM/SIGINT so the init system can stop it.
Future<void> main(List<String> args) async {
  stdout.writeln('worker: starting (pid $pid)');
  ProcessSignal.sigterm.watch().listen((_) => exit(0));

  var tick = 0;
  Timer.periodic(const Duration(seconds: 5), (_) {
    stdout.writeln('worker: heartbeat ${++tick}');
  });
}
