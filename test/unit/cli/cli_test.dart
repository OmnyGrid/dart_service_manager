import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:dart_service_manager/dart_service_manager_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/fake_driver.dart';
import '../../support/fake_process_runner.dart';
import '../../support/in_memory_registry.dart';

void main() {
  late Directory root;
  late Directory packageRoot;
  late InMemoryServiceRegistry registry;
  late FakeServiceDriver driver;
  late DartServiceManager manager;
  late StringBuffer out;
  late StringBuffer err;

  Future<int> cli(List<String> args) => runCli(
    args,
    managerFactory: ({required bool verbose}) => manager,
    out: out,
    errOut: err,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('dsm_cli');
    packageRoot = Directory(p.join(root.path, 'analytics'))..createSync();
    Directory(p.join(packageRoot.path, 'bin')).createSync();
    for (final s in ['worker', 'scheduler']) {
      File(
        p.join(packageRoot.path, 'bin', '$s.dart'),
      ).writeAsStringSync('void main() {}');
    }
    File(p.join(packageRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: analytics
dart_services:
  worker: bin/worker.dart
  scheduler: bin/scheduler.dart
''');
    registry = InMemoryServiceRegistry();
    driver = FakeServiceDriver();
    final runner = FakeProcessRunner(
      responder: (run) {
        final idx = run.args.indexOf('-o');
        if (idx >= 0) File(run.args[idx + 1]).writeAsStringSync('bin');
        return const ProcessRunResult(exitCode: 0);
      },
    );
    manager = DartServiceManager(
      resolver: PackageResolver(workingDirectory: packageRoot),
      manifestLoader: const ManifestLoader(),
      compiler: ServiceCompiler(
        outputDirectory: p.join(root.path, 'out'),
        processRunner: runner,
        dartExecutable: 'dart',
      ),
      registry: registry,
      driver: driver,
    );
    out = StringBuffer();
    err = StringBuffer();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<int> installAll() =>
      cli(['--path', packageRoot.path, 'install', 'analytics']);

  test('install reports success and registers services', () async {
    final code = await installAll();
    expect(code, 0);
    expect(out.toString(), contains('Installed analytics'));
    expect(await registry.all(), hasLength(2));
  });

  test('install a single service via package:service', () async {
    final code = await cli([
      '--path',
      packageRoot.path,
      'install',
      'analytics:worker',
    ]);
    expect(code, 0);
    expect(await registry.all(), hasLength(1));
  });

  test('install honours --scope system', () async {
    await cli([
      '--path',
      packageRoot.path,
      '--scope',
      'system',
      'install',
      'analytics:worker',
    ]);
    expect(
      (await registry.find('analytics', 'worker'))!.scope,
      ServiceScope.system,
    );
  });

  test('list prints installed services with status', () async {
    await installAll();
    driver.defaultStatus = ServiceStatus.running;
    out.clear();
    final code = await cli(['list']);
    expect(code, 0);
    expect(out.toString(), contains('analytics:worker'));
    expect(out.toString(), contains('running'));
  });

  test('packages lists installed packages', () async {
    await installAll();
    out.clear();
    await cli(['packages']);
    expect(out.toString().trim(), 'analytics');
  });

  test('services lists a package\'s services', () async {
    await installAll();
    out.clear();
    await cli(['services', 'analytics']);
    expect(out.toString(), contains('worker'));
    expect(out.toString(), contains('scheduler'));
  });

  test('status of a single service', () async {
    await installAll();
    driver.statuses['analytics:worker'] = ServiceStatus.failed;
    out.clear();
    await cli(['status', 'analytics:worker']);
    expect(out.toString(), contains('failed'));
  });

  test('start applies to all package services when package-wide', () async {
    await installAll();
    out.clear();
    await cli(['start', 'analytics']);
    expect(
      driver.operations,
      containsAll(['start:analytics:worker', 'start:analytics:scheduler']),
    );
    expect(out.toString(), contains('Started analytics:worker'));
  });

  test('stop and uninstall a single service', () async {
    await installAll();
    await cli(['stop', 'analytics:worker']);
    final code = await cli(['uninstall', 'analytics:worker']);
    expect(code, 0);
    expect(await registry.find('analytics', 'worker'), isNull);
  });

  test('restart a single service', () async {
    await installAll();
    out.clear();
    await cli(['restart', 'analytics:worker']);
    expect(driver.operations, contains('restart:analytics:worker'));
    expect(out.toString(), contains('Restarted analytics:worker'));
  });

  test('status package-wide lists every service', () async {
    await installAll();
    out.clear();
    final code = await cli(['status', 'analytics']);
    expect(code, 0);
    expect(out.toString(), contains('analytics:worker'));
    expect(out.toString(), contains('analytics:scheduler'));
  });

  test('pause and resume on a pause-capable driver', () async {
    driver = FakeServiceDriver(platform: 'windows', supportsPauseResume: true);
    manager = DartServiceManager(
      resolver: PackageResolver(workingDirectory: packageRoot),
      manifestLoader: const ManifestLoader(),
      compiler: ServiceCompiler(
        outputDirectory: p.join(root.path, 'out'),
        processRunner: FakeProcessRunner(
          responder: (run) {
            final idx = run.args.indexOf('-o');
            if (idx >= 0) File(run.args[idx + 1]).writeAsStringSync('bin');
            return const ProcessRunResult(exitCode: 0);
          },
        ),
        dartExecutable: 'dart',
      ),
      registry: registry,
      driver: driver,
    );
    await cli(['--path', packageRoot.path, 'install', 'analytics:worker']);
    expect(await cli(['pause', 'analytics:worker']), 0);
    expect(await cli(['resume', 'analytics:worker']), 0);
    expect(
      driver.operations,
      containsAll(['pause:analytics:worker', 'resume:analytics:worker']),
    );
  });

  test('pause on an unsupported platform exits 1', () async {
    await installAll();
    final code = await cli(['pause', 'analytics:worker']);
    expect(code, 1);
    expect(err.toString(), contains('error:'));
  });

  test('list with nothing installed reports empty', () async {
    await cli(['list']);
    expect(out.toString(), contains('No services installed'));
  });

  test('packages with nothing installed reports empty', () async {
    await cli(['packages']);
    expect(out.toString(), contains('No packages'));
  });

  test('services on an empty package reports empty', () async {
    await cli(['services', 'analytics']);
    expect(out.toString(), contains('No services installed'));
  });

  test('services requires exactly one argument', () async {
    expect(await cli(['services']), 64);
  });

  test('list reflects status-query failures via last-known status', () async {
    await installAll();
    driver.throwOnStatus = true;
    out.clear();
    final code = await cli(['list']);
    expect(code, 0);
    expect(out.toString(), contains('analytics:worker'));
  });

  test('missing argument is a usage error (exit 64)', () async {
    final code = await cli(['install']);
    expect(code, 64);
    expect(err.toString(), isNotEmpty);
  });

  test('operating on an unknown service exits 1 with an error', () async {
    final code = await cli(['start', 'analytics:ghost']);
    expect(code, 1);
    expect(err.toString(), contains('error:'));
  });

  test('an unknown command is a usage error', () async {
    final code = await cli(['frobnicate']);
    expect(code, 64);
  });

  group('imperative install (--executable)', () {
    late String exe;
    setUp(() {
      exe = p.join(root.path, 'myapp');
      File(exe).writeAsStringSync('binary');
    });

    test(
      'installs a pre-built executable with policy and passthrough args',
      () async {
        final code = await cli([
          'install',
          'myapp:hub',
          '--executable',
          exe,
          '--restart',
          'on-failure',
          '--no-auto-start',
          '--',
          'hub',
          'start',
        ]);
        expect(code, 0);
        final entry = (await registry.find('myapp', 'hub'))!;
        expect(entry.binaryPath, p.absolute(exe));
        expect(entry.arguments, ['hub', 'start']);
        expect(entry.restart, RestartPolicy.onFailure);
        expect(entry.autoStart, isFalse);
      },
    );

    test('--start-now starts the service', () async {
      await cli(['install', 'myapp:hub', '--executable', exe, '--start-now']);
      expect(driver.operations, contains('start:myapp:hub'));
    });

    test('--dry-run prints the definition and installs nothing', () async {
      final code = await cli([
        'install',
        'myapp:hub',
        '--executable',
        exe,
        '--dry-run',
      ]);
      expect(code, 0);
      expect(out.toString(), contains('rendered:'));
      expect(await registry.find('myapp', 'hub'), isNull);
    });

    test('--dry-run without --executable is a usage error', () async {
      expect(await cli(['install', 'analytics', '--dry-run']), 64);
    });

    test('--executable with a bare package is a usage error', () async {
      expect(await cli(['install', 'analytics', '--executable', exe]), 64);
    });

    test('passthrough args without --executable is a usage error', () async {
      expect(await cli(['install', 'analytics', '--', 'x']), 64);
    });
  });
}
