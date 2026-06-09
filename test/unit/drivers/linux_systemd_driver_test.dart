import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/fake_process_runner.dart';

void main() {
  late Directory home;
  late FakeProcessRunner runner;
  late LinuxSystemdDriver driver;

  ServiceDescriptor descriptor({
    ServiceScope scope = ServiceScope.user,
    List<String> args = const [],
    Map<String, String> env = const {},
  }) => ServiceDescriptor(
    packageName: 'analytics',
    serviceName: 'worker',
    executablePath: '/opt/bin/worker',
    scope: scope,
    description: 'Analytics Worker',
    arguments: args,
    environment: env,
  );

  setUp(() {
    home = Directory.systemTemp.createTempSync('dsm_systemd');
    runner = FakeProcessRunner(
      responder: (run) => run.args.contains('is-active')
          ? const ProcessRunResult(exitCode: 0, stdout: 'active\n')
          : const ProcessRunResult(exitCode: 0),
    );
    driver = LinuxSystemdDriver(
      processRunner: runner,
      environment: {'HOME': home.path},
    );
  });
  tearDown(() => home.deleteSync(recursive: true));

  test('reports the platform and lack of pause support', () {
    expect(driver.platform, 'linux');
    expect(driver.supportsPauseResume, isFalse);
  });

  test('buildUnitFile renders a valid user unit', () {
    final unit = driver.buildUnitFile(
      descriptor(args: ['--port', '80'], env: {'LOG': 'debug'}),
    );
    expect(unit, contains('Description=Analytics Worker'));
    expect(unit, contains('ExecStart=/opt/bin/worker --port 80'));
    expect(unit, contains('Restart=always'));
    expect(unit, contains('Environment="LOG=debug"'));
    expect(unit, contains('WantedBy=default.target'));
  });

  test('buildUnitFile targets multi-user.target for system scope', () {
    final unit = driver.buildUnitFile(descriptor(scope: ServiceScope.system));
    expect(unit, contains('WantedBy=multi-user.target'));
  });

  test('install writes the unit and reloads + enables', () async {
    final svc = descriptor();
    await driver.install(svc);
    expect(File(driver.unitPath(svc)).existsSync(), isTrue);
    expect(
      driver.unitPath(svc),
      p.join(
        home.path,
        '.config',
        'systemd',
        'user',
        'dart_analytics_worker.service',
      ),
    );
    expect(runner.runs.map((r) => r.commandLine), [
      'systemctl --user daemon-reload',
      'systemctl --user enable dart_analytics_worker',
    ]);
  });

  test('start/stop/restart issue the right systemctl verbs', () async {
    final svc = descriptor();
    await driver.start(svc);
    await driver.stop(svc);
    await driver.restart(svc);
    expect(
      runner.runs[0].commandLine,
      'systemctl --user start dart_analytics_worker',
    );
    expect(
      runner.runs[1].commandLine,
      'systemctl --user stop dart_analytics_worker',
    );
    expect(
      runner.runs[2].commandLine,
      'systemctl --user restart dart_analytics_worker',
    );
  });

  test('system scope omits the --user flag', () async {
    await driver.start(descriptor(scope: ServiceScope.system));
    expect(runner.last.commandLine, 'systemctl start dart_analytics_worker');
  });

  test('status maps systemctl is-active output', () async {
    final svc = descriptor();
    await driver.install(svc); // create the unit file so mapping can see it
    expect(await driver.status(svc), ServiceStatus.running);
  });

  test('status maps failed and inactive states', () async {
    final svc = descriptor();
    await driver.install(svc);
    runner = FakeProcessRunner(
      responder: (run) =>
          const ProcessRunResult(exitCode: 3, stdout: 'failed\n'),
    );
    final failingDriver = LinuxSystemdDriver(
      processRunner: runner,
      environment: {'HOME': home.path},
    );
    expect(await failingDriver.status(svc), ServiceStatus.failed);
  });

  test('pause and resume are unsupported', () {
    expect(
      () => driver.pause(descriptor()),
      throwsA(isA<PlatformNotSupportedException>()),
    );
    expect(
      () => driver.resume(descriptor()),
      throwsA(isA<PlatformNotSupportedException>()),
    );
  });

  test('uninstall disables and removes the unit', () async {
    final svc = descriptor();
    await driver.install(svc);
    await driver.uninstall(svc);
    expect(File(driver.unitPath(svc)).existsSync(), isFalse);
    expect(
      runner.runs.map((r) => r.commandLine),
      contains('systemctl --user disable --now dart_analytics_worker'),
    );
  });

  test(
    'status maps an unknown active string to installed when unit exists',
    () async {
      final svc = descriptor();
      await driver.install(svc);
      final weird = LinuxSystemdDriver(
        processRunner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(
            exitCode: 0,
            stdout: 'unknown\n',
          ),
        ),
        environment: {'HOME': home.path},
      );
      expect(await weird.status(svc), ServiceStatus.installed);
    },
  );

  test('status maps inactive to stopped when the unit exists', () async {
    final svc = descriptor();
    await driver.install(svc);
    final inactive = LinuxSystemdDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(
          exitCode: 3,
          stdout: 'inactive\n',
        ),
      ),
      environment: {'HOME': home.path},
    );
    expect(await inactive.status(svc), ServiceStatus.stopped);
  });

  test('system scope writes into /etc/systemd/system', () {
    final svc = descriptor(scope: ServiceScope.system);
    expect(driver.unitPath(svc), startsWith('/etc/systemd/system'));
  });

  test('executable paths with spaces are quoted in ExecStart', () {
    final svc = ServiceDescriptor(
      packageName: 'analytics',
      serviceName: 'worker',
      executablePath: '/opt/my apps/worker',
    );
    expect(
      driver.buildUnitFile(svc),
      contains('ExecStart="/opt/my apps/worker"'),
    );
  });

  test('start throws ServiceStartException on failure', () {
    final failing = LinuxSystemdDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(exitCode: 1, stderr: 'boom'),
      ),
      environment: {'HOME': home.path},
    );
    expect(
      () => failing.start(descriptor()),
      throwsA(isA<ServiceStartException>()),
    );
  });
}
