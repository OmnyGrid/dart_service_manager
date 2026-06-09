import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

import '../../support/fake_process_runner.dart';

void main() {
  late FakeProcessRunner runner;
  late WindowsServiceDriver driver;

  ServiceDescriptor descriptor({List<String> args = const []}) =>
      ServiceDescriptor(
        packageName: 'analytics',
        serviceName: 'worker',
        executablePath: r'C:\bin\worker.exe',
        description: 'Analytics Worker',
        arguments: args,
      );

  setUp(() {
    runner = FakeProcessRunner();
    driver = WindowsServiceDriver(processRunner: runner);
  });

  test('reports platform and pause support', () {
    expect(driver.platform, 'windows');
    expect(driver.supportsPauseResume, isTrue);
  });

  test('buildBinPath quotes the executable and appends args', () {
    expect(driver.buildBinPath(descriptor()), r'"C:\bin\worker.exe"');
    expect(
      driver.buildBinPath(descriptor(args: ['--port', '80'])),
      r'"C:\bin\worker.exe" --port 80',
    );
  });

  test('install calls sc create with binPath and DisplayName', () async {
    await driver.install(descriptor());
    final create = runner.runs.first;
    expect(create.executable, 'sc.exe');
    expect(
      create.args,
      containsAllInOrder(['create', 'dart_analytics_worker']),
    );
    expect(create.args, contains('binPath='));
    expect(create.args, contains(r'"C:\bin\worker.exe"'));
    expect(create.args, containsAllInOrder(['start=', 'auto']));
  });

  test('lifecycle verbs map to sc subcommands', () async {
    await driver.start(descriptor());
    expect(runner.last.args, ['start', 'dart_analytics_worker']);
    await driver.stop(descriptor());
    expect(runner.last.args, ['stop', 'dart_analytics_worker']);
    await driver.pause(descriptor());
    expect(runner.last.args, ['pause', 'dart_analytics_worker']);
    await driver.resume(descriptor());
    expect(runner.last.args, ['continue', 'dart_analytics_worker']);
  });

  test('parseState maps SCM state codes', () {
    expect(driver.parseState('STATE : 4 RUNNING'), ServiceStatus.running);
    expect(driver.parseState('STATE : 1 STOPPED'), ServiceStatus.stopped);
    expect(driver.parseState('STATE : 7 PAUSED'), ServiceStatus.paused);
    expect(driver.parseState('no state here'), ServiceStatus.unknown);
  });

  test('status returns unknown when sc query fails', () async {
    final failing = WindowsServiceDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(exitCode: 1060),
      ),
    );
    expect(await failing.status(descriptor()), ServiceStatus.unknown);
  });

  test('status parses a successful sc query', () async {
    final running = WindowsServiceDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(
          exitCode: 0,
          stdout: 'SERVICE_NAME: dart_analytics_worker\n  STATE : 4 RUNNING',
        ),
      ),
    );
    expect(await running.status(descriptor()), ServiceStatus.running);
  });

  test('uninstall stops then deletes', () async {
    await driver.uninstall(descriptor());
    expect(runner.runs[0].args, ['stop', 'dart_analytics_worker']);
    expect(runner.runs[1].args, ['delete', 'dart_analytics_worker']);
  });

  test('install throws when sc create fails', () {
    final failing = WindowsServiceDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(exitCode: 1, stderr: 'denied'),
      ),
    );
    expect(
      () => failing.install(descriptor()),
      throwsA(isA<ServiceInstallationException>()),
    );
  });

  test('does not support environment files', () {
    expect(driver.supportsEnvironmentFile, isFalse);
  });

  test('autoStart false uses start= demand', () async {
    await driver.install(descriptor().copyWith(autoStart: false));
    final create = runner.runs.first;
    expect(create.args, containsAllInOrder(['start=', 'demand']));
  });

  test('configures SCM failure actions for restart policy', () async {
    await driver.install(
      descriptor().copyWith(restartDelay: const Duration(seconds: 7)),
    );
    final failure = runner.runs.firstWhere((r) => r.args.first == 'failure');
    expect(failure.args, contains('reset='));
    expect(failure.args, contains('7'));
    expect(failure.args, contains('restart/7000'));
  });

  test('never restart configures empty failure actions', () async {
    await driver.install(descriptor().copyWith(restart: RestartPolicy.never));
    final failure = runner.runs.firstWhere((r) => r.args.first == 'failure');
    expect(failure.args, contains(''));
  });

  test('render returns the sc create command line', () {
    final line = driver.render(descriptor());
    expect(line, contains('create dart_analytics_worker'));
    expect(line, contains('start= auto'));
  });

  test('render and install reject an environment file', () {
    final svc = descriptor().copyWith(environmentFile: r'C:\x.env');
    expect(
      () => driver.render(svc),
      throwsA(isA<PlatformNotSupportedException>()),
    );
    expect(
      () => driver.install(svc),
      throwsA(isA<PlatformNotSupportedException>()),
    );
  });

  test('maps access-denied to PermissionDeniedException', () {
    final denied = WindowsServiceDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(
          exitCode: 5,
          stderr: 'Access is denied.',
        ),
      ),
    );
    expect(
      () => denied.start(descriptor()),
      throwsA(isA<PermissionDeniedException>()),
    );
  });
}
