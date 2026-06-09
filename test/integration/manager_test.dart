import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_driver.dart';
import '../support/fake_process_runner.dart';
import '../support/in_memory_registry.dart';

void main() {
  late Directory root;
  late Directory packageRoot;
  late InMemoryServiceRegistry registry;
  late FakeServiceDriver driver;
  late DartServiceManager manager;

  DartServiceManager build({FakeServiceDriver? withDriver}) {
    driver = withDriver ?? FakeServiceDriver();
    final runner = FakeProcessRunner(
      responder: (run) {
        final idx = run.args.indexOf('-o');
        if (idx >= 0) File(run.args[idx + 1]).writeAsStringSync('bin');
        return const ProcessRunResult(exitCode: 0);
      },
    );
    return DartServiceManager(
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
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dsm_manager');
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
    manager = build();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'install (package-wide) compiles, installs and registers all services',
    () async {
      await manager.install('analytics', path: packageRoot.path);
      expect(
        driver.operations,
        containsAll([
          'install:analytics:worker',
          'install:analytics:scheduler',
        ]),
      );
      final entries = await registry.all();
      expect(
        entries.map((e) => e.serviceName),
        containsAll(['worker', 'scheduler']),
      );
      expect(entries.first.platform, 'linux');
    },
  );

  test('install a single service only registers that one', () async {
    await manager.install(
      'analytics',
      serviceName: 'worker',
      path: packageRoot.path,
    );
    final entries = await registry.all();
    expect(entries, hasLength(1));
    expect(entries.single.serviceName, 'worker');
  });

  test('install records the requested scope', () async {
    await manager.install(
      'analytics',
      serviceName: 'worker',
      scope: ServiceScope.system,
      path: packageRoot.path,
    );
    expect(
      (await registry.find('analytics', 'worker'))!.scope,
      ServiceScope.system,
    );
  });

  test('start/stop update the last-known status and call the driver', () async {
    await manager.install(
      'analytics',
      serviceName: 'worker',
      path: packageRoot.path,
    );
    await manager.start('analytics', 'worker');
    expect(driver.operations, contains('start:analytics:worker'));
    expect(
      (await registry.find('analytics', 'worker'))!.status,
      ServiceStatus.running,
    );
    await manager.stop('analytics', 'worker');
    expect(
      (await registry.find('analytics', 'worker'))!.status,
      ServiceStatus.stopped,
    );
  });

  test('restart calls the driver and marks the service running', () async {
    await manager.install(
      'analytics',
      serviceName: 'worker',
      path: packageRoot.path,
    );
    await manager.restart('analytics', 'worker');
    expect(driver.operations, contains('restart:analytics:worker'));
    expect(
      (await registry.find('analytics', 'worker'))!.status,
      ServiceStatus.running,
    );
  });

  test(
    'listServices falls back to last-known status on query failure',
    () async {
      await manager.install('analytics', path: packageRoot.path);
      driver.throwOnStatus = true;
      final services = await manager.listServices();
      expect(services, hasLength(2));
      expect(
        services.every((s) => s.status == ServiceStatus.installed),
        isTrue,
      );
    },
  );

  test('status queries the live driver status', () async {
    await manager.install(
      'analytics',
      serviceName: 'worker',
      path: packageRoot.path,
    );
    driver.statuses['analytics:worker'] = ServiceStatus.failed;
    expect(await manager.status('analytics', 'worker'), ServiceStatus.failed);
  });

  test('listServices annotates entries with live status', () async {
    await manager.install('analytics', path: packageRoot.path);
    driver.defaultStatus = ServiceStatus.running;
    final services = await manager.listServices();
    expect(services, hasLength(2));
    expect(services.every((s) => s.status == ServiceStatus.running), isTrue);
  });

  test('listPackages and listPackageServices reflect the registry', () async {
    await manager.install('analytics', path: packageRoot.path);
    expect(await manager.listPackages(), ['analytics']);
    expect(await manager.listPackageServices('analytics'), hasLength(2));
  });

  test('uninstall removes from the OS and the registry', () async {
    await manager.install('analytics', path: packageRoot.path);
    await manager.uninstall('analytics', serviceName: 'worker');
    expect(driver.operations, contains('uninstall:analytics:worker'));
    expect(await registry.find('analytics', 'worker'), isNull);
    expect(await registry.byPackage('analytics'), hasLength(1));
  });

  test('uninstall package-wide removes everything', () async {
    await manager.install('analytics', path: packageRoot.path);
    await manager.uninstall('analytics');
    expect(await registry.all(), isEmpty);
  });

  test('uninstall deletes the cached binary', () async {
    await manager.install(
      'analytics',
      serviceName: 'worker',
      path: packageRoot.path,
    );
    final binary = (await registry.find('analytics', 'worker'))!.binaryPath;
    expect(File(binary).existsSync(), isTrue);
    await manager.uninstall('analytics', serviceName: 'worker');
    expect(File(binary).existsSync(), isFalse);
  });

  test('operating on an unknown service throws ServiceNotFoundException', () {
    expect(
      () => manager.start('analytics', 'ghost'),
      throwsA(isA<ServiceNotFoundException>()),
    );
    expect(
      () => manager.uninstall('ghost'),
      throwsA(isA<ServiceNotFoundException>()),
    );
  });

  test('pause is rejected on a driver without pause support', () async {
    await manager.install(
      'analytics',
      serviceName: 'worker',
      path: packageRoot.path,
    );
    expect(
      () => manager.pause('analytics', 'worker'),
      throwsA(isA<PlatformNotSupportedException>()),
    );
  });

  test('pause/resume work on a pause-capable driver', () async {
    manager = build(
      withDriver: FakeServiceDriver(
        platform: 'windows',
        supportsPauseResume: true,
      ),
    );
    await manager.install(
      'analytics',
      serviceName: 'worker',
      path: packageRoot.path,
    );
    await manager.pause('analytics', 'worker');
    await manager.resume('analytics', 'worker');
    expect(
      driver.operations,
      containsAll(['pause:analytics:worker', 'resume:analytics:worker']),
    );
    expect(
      (await registry.find('analytics', 'worker'))!.status,
      ServiceStatus.running,
    );
  });
}
