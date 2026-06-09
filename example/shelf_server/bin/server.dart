import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// A small Shelf HTTP server, written to run as a managed OS service via
/// `dart_service_manager`.
///
/// It demonstrates the two things a real service needs:
///
/// * **Configuration from the manifest** — the listening port comes from
///   `--port <n>` (see `dart_services:` `args` in pubspec.yaml), falling back to
///   the `PORT` environment variable, then a default.
/// * **Graceful shutdown** — it stops cleanly when the init system sends
///   `SIGTERM` (systemd/launchd `stop`) or `SIGINT` (Ctrl-C), so the service
///   manager can stop and restart it reliably.
Future<void> main(List<String> args) async {
  final port = _resolvePort(args);
  final startedAt = DateTime.now();
  var requestCount = 0;

  Response handle(Request request) {
    requestCount++;
    final path = '/${request.url.path}';
    switch (path) {
      case '/':
        final uptime = DateTime.now().difference(startedAt);
        return Response.ok(
          'Hello from shelf_server! Up for ${uptime.inSeconds}s.\n',
        );
      case '/health':
        return Response.ok('ok\n');
      case '/metrics':
        final uptime = DateTime.now().difference(startedAt);
        return Response.ok(
          'uptime_seconds ${uptime.inSeconds}\nrequests_total $requestCount\n',
          headers: {'content-type': 'text/plain'},
        );
      default:
        return Response.notFound('not found\n');
    }
  }

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(handle);

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  server.autoCompress = true;
  stdout.writeln(
    'shelf_server listening on http://${server.address.host}:${server.port}',
  );

  // Stop cleanly when the OS service manager (or Ctrl-C) asks us to.
  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('shelf_server: received ${signal.name}, shutting down');
    await server.close(force: true);
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  // SIGTERM is not available on Windows; guard so the example runs everywhere.
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen(shutdown);
  }
}

/// Resolves the listening port from `--port <n>`, then `PORT`, then `8080`.
int _resolvePort(List<String> args) {
  final flag = args.indexOf('--port');
  if (flag >= 0 && flag + 1 < args.length) {
    final parsed = int.tryParse(args[flag + 1]);
    if (parsed != null) return parsed;
  }
  return int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
}
