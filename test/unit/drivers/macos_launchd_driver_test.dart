import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/fake_process_runner.dart';

void main() {
  late Directory home;
  late FakeProcessRunner runner;
  late MacOsLaunchdDriver driver;

  ServiceDescriptor descriptor({Map<String, String> env = const {}}) =>
      ServiceDescriptor(
        packageName: 'analytics',
        serviceName: 'worker',
        executablePath: '/opt/bin/worker',
        description: 'Analytics Worker',
        environment: env,
      );

  setUp(() {
    home = Directory.systemTemp.createTempSync('dsm_launchd');
    runner = FakeProcessRunner();
    driver = MacOsLaunchdDriver(
      processRunner: runner,
      environment: {'HOME': home.path},
    );
  });
  tearDown(() => home.deleteSync(recursive: true));

  test('reports platform and no pause support', () {
    expect(driver.platform, 'macos');
    expect(driver.supportsPauseResume, isFalse);
  });

  test('buildPlist renders a valid agent plist', () {
    final plist = driver.render(descriptor(env: {'LOG': 'debug'}));
    expect(plist, contains('<key>Label</key>'));
    expect(
      plist,
      contains('<string>com.dartservices.analytics.worker</string>'),
    );
    expect(plist, contains('<string>/opt/bin/worker</string>'));
    expect(plist, contains('<key>RunAtLoad</key>'));
    expect(plist, contains('<key>EnvironmentVariables</key>'));
    expect(plist, contains('<key>LOG</key>'));
  });

  test('install writes the plist and loads it', () async {
    final svc = descriptor();
    await driver.install(svc);
    expect(
      driver.plistPath(svc),
      p.join(
        home.path,
        'Library',
        'LaunchAgents',
        'com.dartservices.analytics.worker.plist',
      ),
    );
    expect(File(driver.plistPath(svc)).existsSync(), isTrue);
    expect(
      runner.last.commandLine,
      'launchctl load -w ${driver.plistPath(svc)}',
    );
  });

  test('start and stop call launchctl with the label', () async {
    await driver.start(descriptor());
    expect(
      runner.last.commandLine,
      'launchctl start com.dartservices.analytics.worker',
    );
    await driver.stop(descriptor());
    expect(
      runner.last.commandLine,
      'launchctl stop com.dartservices.analytics.worker',
    );
  });

  test('status parses a running PID from launchctl list', () async {
    final running = MacOsLaunchdDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(
          exitCode: 0,
          stdout: '{\n  "PID" = 4321;\n  "Label" = "x";\n}',
        ),
      ),
      environment: {'HOME': home.path},
    );
    expect(await running.status(descriptor()), ServiceStatus.running);
  });

  test('status parses a non-zero last exit as failed', () async {
    final failed = MacOsLaunchdDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(
          exitCode: 0,
          stdout: '{\n  "LastExitStatus" = 256;\n}',
        ),
      ),
      environment: {'HOME': home.path},
    );
    expect(await failed.status(descriptor()), ServiceStatus.failed);
  });

  test('status returns unknown when not loaded and no plist', () async {
    final notLoaded = MacOsLaunchdDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(exitCode: 1),
      ),
      environment: {'HOME': home.path},
    );
    expect(await notLoaded.status(descriptor()), ServiceStatus.unknown);
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

  test('uninstall unloads and removes the plist', () async {
    final svc = descriptor();
    await driver.install(svc);
    await driver.uninstall(svc);
    expect(File(driver.plistPath(svc)).existsSync(), isFalse);
    expect(
      runner.runs.map((r) => r.commandLine),
      contains('launchctl unload -w ${driver.plistPath(svc)}'),
    );
  });

  test('restart stops then starts via launchctl', () async {
    await driver.restart(descriptor());
    expect(runner.runs[0].args, ['stop', 'com.dartservices.analytics.worker']);
    expect(runner.runs[1].args, ['start', 'com.dartservices.analytics.worker']);
  });

  test('system scope installs into /Library/LaunchDaemons', () {
    final svc = ServiceDescriptor(
      packageName: 'analytics',
      serviceName: 'worker',
      executablePath: '/opt/bin/worker',
      scope: ServiceScope.system,
    );
    expect(driver.plistPath(svc), startsWith('/Library/LaunchDaemons'));
  });

  test(
    'status returns stopped when a plist exists but it is not loaded',
    () async {
      final svc = descriptor();
      await driver.install(svc); // writes the plist
      final notLoaded = MacOsLaunchdDriver(
        processRunner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(exitCode: 1),
        ),
        environment: {'HOME': home.path},
      );
      expect(await notLoaded.status(svc), ServiceStatus.stopped);
    },
  );

  test('buildPlist escapes XML special characters', () {
    final svc = ServiceDescriptor(
      packageName: 'analytics',
      serviceName: 'worker',
      executablePath: '/opt/bin/worker',
      environment: {'X': 'a<b>&c'},
    );
    expect(driver.render(svc), contains('a&lt;b&gt;&amp;c'));
  });

  test('stop throws ServiceStopException on failure', () {
    final failing = MacOsLaunchdDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(exitCode: 1, stderr: 'no'),
      ),
      environment: {'HOME': home.path},
    );
    expect(
      () => failing.stop(descriptor()),
      throwsA(isA<ServiceStopException>()),
    );
  });

  test('start throws ServiceStartException on failure', () {
    final failing = MacOsLaunchdDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(exitCode: 1, stderr: 'no'),
      ),
      environment: {'HOME': home.path},
    );
    expect(
      () => failing.start(descriptor()),
      throwsA(isA<ServiceStartException>()),
    );
  });

  test('install throws when launchctl load fails', () {
    final failing = MacOsLaunchdDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(exitCode: 1, stderr: 'nope'),
      ),
      environment: {'HOME': home.path},
    );
    expect(
      () => failing.install(descriptor()),
      throwsA(isA<ServiceInstallationException>()),
    );
  });

  test('does not support environment files', () {
    expect(driver.supportsEnvironmentFile, isFalse);
  });

  ServiceDescriptor policy({
    RestartPolicy restart = RestartPolicy.always,
    bool autoStart = true,
    Duration restartDelay = const Duration(seconds: 5),
    Duration? stopTimeout,
  }) => ServiceDescriptor(
    packageName: 'analytics',
    serviceName: 'worker',
    executablePath: '/opt/bin/worker',
    restart: restart,
    autoStart: autoStart,
    restartDelay: restartDelay,
    stopTimeout: stopTimeout,
  );

  test('render maps on-failure to a KeepAlive dict', () {
    final plist = driver.render(policy(restart: RestartPolicy.onFailure));
    expect(plist, contains('<key>KeepAlive</key>'));
    expect(plist, contains('<key>SuccessfulExit</key>'));
    expect(plist, contains('<false/>'));
  });

  test('render maps never restart to KeepAlive false', () {
    final plist = driver.render(policy(restart: RestartPolicy.never));
    expect(plist, contains('<key>KeepAlive</key>\n  <false/>'));
  });

  test('render disables RunAtLoad when autoStart is false', () {
    final plist = driver.render(policy(autoStart: false));
    expect(plist, contains('<key>RunAtLoad</key>\n  <false/>'));
  });

  test('render emits ThrottleInterval and ExitTimeOut when set', () {
    final plist = driver.render(
      policy(
        restartDelay: const Duration(seconds: 20),
        stopTimeout: const Duration(seconds: 8),
      ),
    );
    expect(plist, contains('<key>ThrottleInterval</key>'));
    expect(plist, contains('<integer>20</integer>'));
    expect(plist, contains('<key>ExitTimeOut</key>'));
    expect(plist, contains('<integer>8</integer>'));
  });

  test('render rejects an environment file', () {
    expect(
      () => driver.render(descriptor().copyWith(environmentFile: '/etc/x.env')),
      throwsA(isA<PlatformNotSupportedException>()),
    );
  });

  test('maps permission failures to PermissionDeniedException', () {
    final denied = MacOsLaunchdDriver(
      processRunner: FakeProcessRunner(
        defaultResult: const ProcessRunResult(
          exitCode: 1,
          stderr: 'Operation not permitted',
        ),
      ),
      environment: {'HOME': home.path},
    );
    expect(
      () => denied.start(descriptor()),
      throwsA(isA<PermissionDeniedException>()),
    );
  });
}
