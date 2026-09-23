// Drives the host's real init system (systemd --user on Linux, launchd user
// agents on macOS) through DartServiceManager. Tagged `os-<platform>`, which
// dart_test.yaml skips by default; run with e.g. `dart test -t os-macos
// --run-skipped test/integration/host_service_test.dart`.
//
// Every service is user-scoped, uses a per-run package name, and is uninstalled
// in tearDown, so a run leaves nothing behind. The registry lives in a temp dir.
@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A long-running program on every POSIX host: `sleep 3600`.
const _sleep = '/bin/sleep';
const _command = ['3600'];

void main() {
  final packageName = 'dsm_it_$pid';
  late Directory temp;
  late DartServiceManager manager;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('dsm_host_');
    manager = DartServiceManager.forCurrentPlatform(
      storagePaths: StoragePaths(
        environment: {
          ...Platform.environment,
          'HOME': temp.path,
          'XDG_DATA_HOME': temp.path,
        },
      ),
    );
  });

  tearDown(() async {
    try {
      await manager.uninstall(packageName);
    } on ServiceManagerException {
      // Nothing installed (or already gone): fine.
    }
    temp.deleteSync(recursive: true);
  });

  ServiceDescriptor descriptor(
    String service, {
    required String executable,
    required List<String> arguments,
    String? scriptPath,
  }) => ServiceDescriptor(
    packageName: packageName,
    serviceName: service,
    executablePath: executable,
    arguments: arguments,
    scriptPath: scriptPath,
    // No auto-restart: `stop` must stick, and a broken command must show up as
    // a service that is not running rather than a restart loop.
    restart: RestartPolicy.never,
  );

  /// Polls the service's live status until it is [expected], failing after
  /// [timeout] with the last status seen.
  Future<void> waitForStatus(
    String service,
    ServiceStatus expected, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var last = ServiceStatus.unknown;
    while (DateTime.now().isBefore(deadline)) {
      last = await manager.status(packageName, service);
      if (last == expected) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    fail('$packageName:$service: expected $expected, last saw $last');
  }

  /// Writes a Dart program that stays alive for an hour, ignoring arguments.
  String writeScript(String name) {
    final file = File(p.join(temp.path, name))
      ..writeAsStringSync(
        "import 'dart:async';\n"
        'void main(List<String> args) => '
        'Timer(const Duration(hours: 1), () {});\n',
      );
    return file.path;
  }

  group(
    'real ${Platform.operatingSystem} init system',
    () {
      test('install, stop, start and uninstall a service', () async {
        await manager.installDescriptor(
          descriptor('life', executable: _sleep, arguments: _command),
          startNow: true,
        );
        await waitForStatus('life', ServiceStatus.running);

        final info = await manager.describe(packageName, 'life');
        expect(info.entry.binaryPath, _sleep);
        expect(info.entry.commandLine, _command);
        expect(info.definition, contains(_sleep));

        await manager.stop(packageName, 'life');
        await waitForStatus('life', ServiceStatus.stopped);

        await manager.start(packageName, 'life');
        await waitForStatus('life', ServiceStatus.running);

        await manager.uninstall(packageName, serviceName: 'life');
        expect(await manager.registry.find(packageName, 'life'), isNull);
        expect(
          () => manager.describe(packageName, 'life'),
          throwsA(isA<ServiceNotFoundException>()),
        );
      });

      test('a Dart VM service runs `dart <script> <command>`', () async {
        final dart = Platform.resolvedExecutable;
        final script = writeScript('vm_service.dart');
        await manager.installDescriptor(
          descriptor(
            'vm',
            executable: dart,
            arguments: [script, ..._command],
            scriptPath: script,
          ),
          startNow: true,
        );
        await waitForStatus('vm', ServiceStatus.running);

        final entry = (await manager.registry.find(packageName, 'vm'))!;
        expect(entry.scriptPath, script);
        expect(entry.arguments, _command);
      });

      test(
        'reinstall under a new Dart VM script runs only that script',
        () async {
          final dart = Platform.resolvedExecutable;
          final oldScript = writeScript('old.dart');
          final newScript = writeScript('new.dart');
          await manager.installDescriptor(
            descriptor(
              'upgrade',
              executable: dart,
              arguments: [oldScript, ..._command],
              scriptPath: oldScript,
            ),
          );

          // What a consumer does on reinstall: re-derive for the current runtime
          // from the recorded command (here, an SDK upgrade renamed the script).
          final recorded = (await manager.describe(
            packageName,
            'upgrade',
          )).entry;
          final resolved = ServiceDescriptor.resolveSelfExecutable(
            resolvedExecutable: dart,
            script: newScript,
            arguments: recorded.arguments,
          );
          await manager.reinstall(
            descriptor(
              'upgrade',
              executable: resolved.executable,
              arguments: resolved.arguments,
              scriptPath: resolved.script,
            ),
          );
          await waitForStatus('upgrade', ServiceStatus.running);

          final info = await manager.describe(packageName, 'upgrade');
          expect(info.entry.commandLine, [newScript, ..._command]);
          expect(info.definition, contains(newScript));
          expect(info.definition, isNot(contains(oldScript)));
        },
      );

      test('reinstall as a native binary drops the Dart VM script', () async {
        final script = writeScript('jit.dart');
        await manager.installDescriptor(
          descriptor(
            'native',
            executable: Platform.resolvedExecutable,
            arguments: [script, ..._command],
            scriptPath: script,
          ),
        );

        // Now "running" as a native binary. Carrying the script over would run
        // `sleep <script> 3600`, which exits at once instead of staying up.
        final recorded = (await manager.describe(packageName, 'native')).entry;
        final resolved = ServiceDescriptor.resolveSelfExecutable(
          resolvedExecutable: _sleep,
          script: _sleep,
          arguments: recorded.arguments,
        );
        await manager.reinstall(
          descriptor(
            'native',
            executable: resolved.executable,
            arguments: resolved.arguments,
            scriptPath: resolved.script,
          ),
        );
        await waitForStatus('native', ServiceStatus.running);

        final info = await manager.describe(packageName, 'native');
        expect(info.entry.binaryPath, _sleep);
        expect(info.entry.scriptPath, isNull);
        expect(info.entry.commandLine, _command);
        expect(info.definition, isNot(contains(script)));
      });

      test('a registry written before 1.4.0 reinstalls cleanly', () async {
        final script = writeScript('legacy.dart');
        await manager.installDescriptor(
          descriptor(
            'legacy',
            executable: Platform.resolvedExecutable,
            arguments: [script, ..._command],
            scriptPath: script,
          ),
        );

        // Rewrite the entry the way 1.3.x stored it: the script inside `args`
        // and no `script` key.
        final registryFile = File(
          (manager.registry as JsonServiceRegistry).filePath,
        );
        final document =
            jsonDecode(registryFile.readAsStringSync()) as Map<String, dynamic>;
        final stored = (document['services'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((e) => e['service'] == 'legacy');
        stored
          ..['args'] = [script, ..._command]
          ..remove('script');
        registryFile.writeAsStringSync(jsonEncode(document));

        final recorded = (await manager.describe(packageName, 'legacy')).entry;
        expect(recorded.scriptPath, script);
        expect(recorded.arguments, _command);

        final resolved = ServiceDescriptor.resolveSelfExecutable(
          resolvedExecutable: _sleep,
          script: _sleep,
          arguments: recorded.arguments,
        );
        await manager.reinstall(
          descriptor(
            'legacy',
            executable: resolved.executable,
            arguments: resolved.arguments,
            scriptPath: resolved.script,
          ),
          startNow: true,
        );
        await waitForStatus('legacy', ServiceStatus.running);
      });
    },
    tags: 'os-${Platform.operatingSystem}',
    // A Dart VM service compiles its script on first start.
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
