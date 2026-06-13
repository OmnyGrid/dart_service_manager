import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:dart_service_manager/src/drivers/windows_task_scheduler_driver.dart';
import 'package:test/test.dart';

import '../../support/fake_process_runner.dart';

/// A deterministic Windows storage layout, independent of the test host.
StoragePaths _paths() => StoragePaths(
  operatingSystem: 'windows',
  environment: {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
);

ServiceDescriptor _descriptor({
  ServiceScope scope = ServiceScope.system,
  Map<String, String> environment = const {},
  List<String> arguments = const ['node', 'start', '--hub', 'wss://h:8443'],
  String executablePath = r'C:\Program Files\App\app.exe',
}) => ServiceDescriptor(
  packageName: 'omnyshell',
  serviceName: 'node',
  executablePath: executablePath,
  scope: scope,
  arguments: arguments,
  environment: environment,
);

void main() {
  late FakeProcessRunner runner;
  late WindowsTaskSchedulerDriver driver;

  setUp(() {
    runner = FakeProcessRunner();
    driver = WindowsTaskSchedulerDriver(
      processRunner: runner,
      storagePaths: _paths(),
    );
  });

  test('reports platform and lacks pause/resume + env-file support', () {
    expect(driver.platform, 'windows');
    expect(driver.supportsPauseResume, isFalse);
    expect(driver.supportsEnvironmentFile, isFalse);
    expect(
      () => driver.pause(_descriptor()),
      throwsA(isA<PlatformNotSupportedException>()),
    );
    expect(
      () => driver.resume(_descriptor()),
      throwsA(isA<PlatformNotSupportedException>()),
    );
  });

  group('taskName + schtasks argument vectors', () {
    test('namespaces the service under a package folder', () {
      expect(taskName(_descriptor()), r'\omnyshell\node');
    });

    test('create/run/end/delete/query are well-formed', () {
      const tn = r'\omnyshell\node';
      expect(createArgs(tn, r'C:\t.xml'), [
        '/Create',
        '/TN',
        tn,
        '/XML',
        r'C:\t.xml',
      ]);
      expect(createArgs(tn, r'C:\t.xml', force: true), contains('/F'));
      expect(runArgs(tn), ['/Run', '/TN', tn]);
      expect(endArgs(tn), ['/End', '/TN', tn]);
      expect(deleteArgs(tn), ['/Delete', '/TN', tn, '/F']);
      expect(queryArgs(tn), ['/Query', '/TN', tn, '/FO', 'LIST', '/V']);
    });
  });

  group('parseState', () {
    test('maps schtasks status words to ServiceStatus', () {
      expect(parseState('Status:    Running'), ServiceStatus.running);
      expect(parseState('Status: Ready'), ServiceStatus.installed);
      expect(parseState('Status: Disabled'), ServiceStatus.stopped);
      expect(parseState('no status here'), ServiceStatus.unknown);
    });
  });

  group('buildTaskXml', () {
    test('system scope runs at boot as LocalSystem, elevated', () {
      final xml = buildTaskXml(
        _descriptor(scope: ServiceScope.system),
        logPath: r'C:\log\node.log',
      );
      expect(xml, contains('<BootTrigger>'));
      expect(xml, contains('<UserId>S-1-5-18</UserId>'));
      expect(xml, contains('<RunLevel>HighestAvailable</RunLevel>'));
    });

    test('user scope runs at logon with an S4U token', () {
      final xml = buildTaskXml(
        _descriptor(scope: ServiceScope.user),
        logPath: r'C:\log\node.log',
        currentUser: r'DOMAIN\me',
      );
      expect(xml, contains('<LogonTrigger>'));
      expect(xml, contains('<LogonType>S4U</LogonType>'));
      expect(xml, contains(r'<UserId>DOMAIN\me</UserId>'));
    });

    test('wraps the command in cmd.exe with env, args and log redirect', () {
      final xml = buildTaskXml(
        _descriptor(environment: const {'APP_HOME': r'D:\data'}),
        logPath: r'C:\log\node.log',
      );
      expect(xml, contains('<Command>cmd.exe</Command>'));
      expect(xml, contains(r'set &quot;APP_HOME=D:\data&quot;'));
      expect(xml, contains('node start --hub wss://h:8443'));
      // The log path has no spaces, so `_cmdQuote` leaves it unquoted.
      expect(xml, contains(r'&gt;&gt; C:\log\node.log 2&gt;&amp;1'));
    });
  });

  test('encodeUtf16Le prefixes a LE BOM and encodes ASCII as 2 bytes', () {
    expect(encodeUtf16Le('AB'), [0xFF, 0xFE, 0x41, 0x00, 0x42, 0x00]);
  });

  group('runtime staging', () {
    ServiceDescriptor pubGlobal() => _descriptor(
      executablePath: r'C:\dart\bin\dart.exe',
      arguments: const [
        r'C:\Users\me\AppData\Local\Pub\Cache\global_packages\omnyshell\bin\omnyshell.dart-3.9.1.snapshot',
        'node',
        'start',
      ],
    );

    test('rewrites a dart-VM launch to a private copy of the snapshot', () {
      final staged = driver.stagedDescriptor(pubGlobal());
      expect(staged.executablePath, r'C:\dart\bin\dart.exe');
      expect(
        staged.arguments.first,
        endsWith(
          r'\dart_service_manager\bin\omnyshell-node-omnyshell.dart-3.9.1.snapshot',
        ),
      );
      expect(staged.arguments.sublist(1), const ['node', 'start']);
    });

    test('rewrites an AOT executable to its staged copy', () {
      final staged = driver.stagedDescriptor(
        _descriptor(executablePath: r'C:\build\app.exe'),
      );
      expect(
        staged.executablePath,
        endsWith(r'\dart_service_manager\bin\omnyshell-node-app.exe'),
      );
      expect(staged.arguments, const [
        'node',
        'start',
        '--hub',
        'wss://h:8443',
      ]);
    });

    test('is idempotent: an already-staged descriptor is unchanged', () {
      final once = driver.stagedDescriptor(
        _descriptor(executablePath: r'C:\build\app.exe'),
      );
      expect(identical(driver.stagedDescriptor(once), once), isTrue);
    });

    test('render reflects the staged path without copying anything', () {
      final out = driver.render(pubGlobal());
      expect(out, contains(r'\dart_service_manager\bin\omnyshell-node-'));
      expect(out, isNot(contains('global_packages')));
    });
  });

  group('lifecycle via the fake runner', () {
    test('start invokes schtasks /Run', () async {
      await driver.start(_descriptor());
      expect(runner.last.executable, 'schtasks.exe');
      expect(runner.last.args, ['/Run', '/TN', r'\omnyshell\node']);
    });

    test('an access-denied failure surfaces PermissionDeniedException', () {
      final denied = WindowsTaskSchedulerDriver(
        processRunner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(
            exitCode: 1,
            stderr: 'ERROR: Access is denied.',
          ),
        ),
        storagePaths: _paths(),
      );
      expect(
        () => denied.start(_descriptor()),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('status maps the query output, and unknown on failure', () async {
      final running = WindowsTaskSchedulerDriver(
        processRunner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(
            exitCode: 0,
            stdout: 'TaskName: x\r\nStatus:    Running\r\n',
          ),
        ),
        storagePaths: _paths(),
      );
      expect(await running.status(_descriptor()), ServiceStatus.running);

      final missing = WindowsTaskSchedulerDriver(
        processRunner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(
            exitCode: 1,
            stderr: 'not found',
          ),
        ),
        storagePaths: _paths(),
      );
      expect(await missing.status(_descriptor()), ServiceStatus.unknown);
    });

    test('uninstall ends then deletes the task', () async {
      await driver.uninstall(_descriptor());
      expect(
        runner.runs.map((r) => r.args.first),
        containsAllInOrder(['/End', '/Delete']),
      );
    });
  });
}
