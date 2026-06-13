import 'dart:io';

import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../models/service_descriptor.dart';
import '../models/service_scope.dart';
import '../models/service_status.dart';
import '../process/process_runner.dart';
import '../registry/storage_paths.dart';
import 'permission_classifier.dart';
import 'platform_service_driver.dart';

/// A [PlatformServiceDriver] for Windows that runs services as **Task Scheduler**
/// tasks (via `schtasks.exe`) instead of Service Control Manager services.
///
/// A plain compiled Dart (or other console) executable cannot perform the
/// in-process SCM handshake (`StartServiceCtrlDispatcher` → `SetServiceStatus`),
/// so registering it as an SCM service yields error 1053 ("did not respond to
/// the start … in time"). Task Scheduler runs ordinary console programs as
/// background daemons with no such requirement, so this driver installs a
/// boot/logon-triggered task that auto-restarts on failure — the right choice
/// for the common "install my CLI as a service" case. Select it with
/// `WindowsServiceBackend.taskScheduler` (see [ServiceDriverFactory]).
///
/// To survive omnyshell-style `dart pub global activate` installs — where the
/// launched snapshot lives in the Windows-locked pub cache — [install] stages a
/// private copy of the runtime under [StoragePaths.binDirectory] and points the
/// task at that copy (see [stageRuntime]). It has no true pause/resume.
final class WindowsTaskSchedulerDriver implements PlatformServiceDriver {
  /// The runner used to invoke `schtasks.exe`/`sc.exe`.
  final ProcessRunner processRunner;

  /// The logger for lifecycle progress.
  final ServiceLogger logger;

  /// Where the staged runtime copy and the log file live.
  final StoragePaths storagePaths;

  /// The `schtasks.exe` executable name or path.
  final String schtasksPath;

  /// The `sc.exe` executable name or path (used only to clear a stale SCM
  /// registration of the same name on install).
  final String scPath;

  /// Creates a Task Scheduler driver.
  WindowsTaskSchedulerDriver({
    required this.processRunner,
    this.logger = const SilentServiceLogger(),
    StoragePaths? storagePaths,
    this.schtasksPath = 'schtasks.exe',
    this.scPath = 'sc.exe',
  }) : storagePaths = storagePaths ?? StoragePaths();

  @override
  String get platform => 'windows';

  @override
  bool get supportsPauseResume => false;

  @override
  bool get supportsEnvironmentFile => false;

  @override
  Future<void> install(ServiceDescriptor service) async {
    final tn = taskName(service);

    // Stop any running instance first so its lock on the staged runtime is
    // released and the copy below can overwrite it (best effort: the task may
    // not be installed or running).
    await processRunner.run(schtasksPath, endArgs(tn));

    // Stage a private copy of the runtime so the task does not depend on the
    // volatile, Windows-locked pub-cache snapshot. See [stageRuntime].
    final staged = stageRuntime(service);

    final log = logPathFor(staged);
    Directory(_parentDir(log)).createSync(recursive: true);

    // Best-effort removal of a prior SCM registration of the same name so the
    // two Windows backends do not collide.
    await processRunner.run(scPath, ['delete', service.systemName]);

    final xml = buildTaskXml(staged, logPath: log, currentUser: _currentUser());
    // `schtasks /Create /XML` requires a UTF-16 file; a UTF-8 one fails with
    // "cannot switch encoding".
    final tmpDir = Directory.systemTemp.createTempSync('dsm_task');
    final tmp = File('${tmpDir.path}${Platform.pathSeparator}$xmlBasename')
      ..writeAsBytesSync(encodeUtf16Le(xml));
    try {
      // Always `/F` so install replaces an orphaned task of the same name; the
      // manager's `force` flag guards the registry-level "already installed".
      await _check(
        schtasksPath,
        createArgs(tn, tmp.path, force: true),
        'create task',
        ServiceInstallationException.new,
      );
    } finally {
      try {
        tmpDir.deleteSync(recursive: true);
      } on Object {
        // Temp cleanup is best-effort.
      }
    }
    logger.info('Installed Task Scheduler task $tn');
  }

  @override
  Future<void> uninstall(ServiceDescriptor service) async {
    final tn = taskName(service);
    await processRunner.run(schtasksPath, endArgs(tn)); // best effort
    await _check(
      schtasksPath,
      deleteArgs(tn),
      'delete task',
      ServiceInstallationException.new,
    );
    cleanStagedRuntime(service);
    logger.info('Uninstalled Task Scheduler task $tn');
  }

  @override
  String render(ServiceDescriptor service) {
    final staged = stagedDescriptor(service);
    final tn = taskName(staged);
    final xml = buildTaskXml(
      staged,
      logPath: logPathFor(staged),
      currentUser: _currentUser(),
    );
    final cmd = [schtasksPath, ...createArgs(tn, '<generated>.xml')].join(' ');
    return '# Task Scheduler definition for $tn\n$xml\n# Install command:\n$cmd';
  }

  @override
  Future<void> start(ServiceDescriptor service) => _check(
    schtasksPath,
    runArgs(taskName(service)),
    'start task',
    ServiceStartException.new,
  );

  @override
  Future<void> stop(ServiceDescriptor service) => _check(
    schtasksPath,
    endArgs(taskName(service)),
    'stop task',
    ServiceStopException.new,
  );

  @override
  Future<void> pause(ServiceDescriptor service) =>
      throw const PlatformNotSupportedException(
        'Task Scheduler has no pause/resume; stop and start the task instead.',
      );

  @override
  Future<void> resume(ServiceDescriptor service) =>
      throw const PlatformNotSupportedException(
        'Task Scheduler has no pause/resume; stop and start the task instead.',
      );

  @override
  Future<void> restart(ServiceDescriptor service) async {
    await processRunner.run(schtasksPath, endArgs(taskName(service)));
    await start(service);
  }

  @override
  Future<ServiceStatus> status(ServiceDescriptor service) async {
    final res = await processRunner.run(
      schtasksPath,
      queryArgs(taskName(service)),
    );
    if (!res.succeeded) return ServiceStatus.unknown;
    return parseState(res.stdout);
  }

  // --- runtime staging -------------------------------------------------------

  /// The directory holding the service's staged runtime copy.
  String runtimeDir(ServiceDescriptor d) => _winNorm(storagePaths.binDirectory);

  /// The log file the task appends stdout/stderr to.
  String logPathFor(ServiceDescriptor d) =>
      '${_winNorm(storagePaths.dataDirectory)}\\logs'
      '\\${d.packageName}-${d.serviceName}.log';

  /// Where [stageRuntime] writes the private copy:
  /// `<binDir>\<package>-<service>-<runtimeFile>`.
  String stagedRuntimePath(ServiceDescriptor d) =>
      '${runtimeDir(d)}\\${d.packageName}-${d.serviceName}-'
      '${_basename(_runtimeSource(d))}';

  /// [d] rewritten to launch the staged copy, **without** performing the copy
  /// (used by [render]). Returns [d] unchanged when it already points at the
  /// staged path.
  ServiceDescriptor stagedDescriptor(ServiceDescriptor d) {
    // Already staged (the runtime lives in our bin dir): leave it untouched so
    // re-staging does not re-prefix the filename.
    if (_samePath(_parentDir(_runtimeSource(d)), runtimeDir(d))) return d;
    final target = stagedRuntimePath(d);
    return _isDartVm(d)
        ? d.copyWith(arguments: [target, ...d.arguments.skip(1)])
        : d.copyWith(executablePath: target);
  }

  /// Copies [d]'s runtime into [runtimeDir] and returns [d] rewritten to launch
  /// that private copy.
  ///
  /// A `dart pub global activate` install runs as `dart <snapshot>`, where the
  /// snapshot lives in the per-SDK pub cache and is **locked by Windows while
  /// the service runs** — so updating the package can't rewrite it, and a later
  /// uninstall+reinstall just re-pins the same stale bytes. Staging a copy in a
  /// service-owned directory decouples the task from the pub cache, and every
  /// (re)install refreshes this copy from the currently-running version.
  ServiceDescriptor stageRuntime(ServiceDescriptor d) {
    final rewritten = stagedDescriptor(d);
    if (identical(rewritten, d)) return d; // already staged: nothing to copy
    Directory(runtimeDir(d)).createSync(recursive: true);
    _copyOverwrite(_runtimeSource(d), stagedRuntimePath(d));
    return rewritten;
  }

  /// Best-effort removal of the staged runtime(s) for [d]; called on uninstall.
  void cleanStagedRuntime(ServiceDescriptor d) {
    final dir = Directory(runtimeDir(d));
    if (!dir.existsSync()) return;
    final prefix = '${d.packageName}-${d.serviceName}-'.toLowerCase();
    for (final f in dir.listSync().whereType<File>()) {
      if (_basename(f.path).toLowerCase().startsWith(prefix)) {
        try {
          f.deleteSync();
        } on Object {
          // May still be locked; leave it for the next install to overwrite.
        }
      }
    }
  }

  /// Whether [d] launches via the Dart VM (`dart <snapshot> …`), as a
  /// `pub global activate` install does — in which case the real program is
  /// `arguments.first` rather than the executable (which is the VM).
  bool _isDartVm(ServiceDescriptor d) {
    final base = _basename(d.executablePath).toLowerCase();
    return (base == 'dart' || base == 'dart.exe') && d.arguments.isNotEmpty;
  }

  /// The path of the runtime file [d] depends on: the snapshot/script for a
  /// Dart-VM (pub-global) launch, else the AOT executable itself.
  String _runtimeSource(ServiceDescriptor d) =>
      _isDartVm(d) ? d.arguments.first : d.executablePath;

  /// Copies [source] over [target], retrying briefly: Windows may hold the old
  /// copy locked for a moment after the task that ran it is stopped.
  void _copyOverwrite(String source, String target) {
    for (var attempt = 0; ; attempt++) {
      try {
        File(source).copySync(target);
        return;
      } on FileSystemException {
        if (attempt >= 10) rethrow;
        sleep(const Duration(milliseconds: 200));
      }
    }
  }

  // --- helpers ---------------------------------------------------------------

  Future<void> _check(
    String exe,
    List<String> args,
    String what,
    ServiceManagerException Function(String, {Object? cause}) onError,
  ) async {
    final res = await processRunner.run(exe, args);
    if (!res.succeeded) {
      final out = res.stderr.trim().isNotEmpty
          ? res.stderr.trim()
          : res.stdout.trim();
      final message =
          'failed to $what (exit ${res.exitCode})'
          '${out.isEmpty ? '' : ': $out'}';
      if (isPermissionFailure(res)) throw PermissionDeniedException(message);
      throw onError(message);
    }
  }

  String? _currentUser() {
    final env = Platform.environment;
    final user = env['USERNAME'];
    if (user == null || user.isEmpty) return null;
    final domain = env['USERDOMAIN'];
    return (domain == null || domain.isEmpty) ? user : '$domain\\$user';
  }
}

/// The task name (folder + leaf) for [d], e.g. `\omnyshell\node`.
String taskName(ServiceDescriptor d) => '\\${d.packageName}\\${d.serviceName}';

/// The filename written into the temp dir before `schtasks /Create /XML`.
const xmlBasename = 'dart_service_task.xml';

/// `schtasks` argument vector that imports [xmlPath] as task [tn].
List<String> createArgs(String tn, String xmlPath, {bool force = false}) => [
  '/Create',
  '/TN',
  tn,
  '/XML',
  xmlPath,
  if (force) '/F',
];

/// `schtasks` argument vector to start task [tn] on demand.
List<String> runArgs(String tn) => ['/Run', '/TN', tn];

/// `schtasks` argument vector to stop task [tn].
List<String> endArgs(String tn) => ['/End', '/TN', tn];

/// `schtasks` argument vector to delete task [tn].
List<String> deleteArgs(String tn) => ['/Delete', '/TN', tn, '/F'];

/// `schtasks` argument vector to query task [tn] in verbose list form.
List<String> queryArgs(String tn) => ['/Query', '/TN', tn, '/FO', 'LIST', '/V'];

/// Encodes [s] as UTF-16 little-endian with a leading BOM — the encoding
/// `schtasks /Create /XML` requires (a UTF-8 file is rejected with "cannot
/// switch encoding").
List<int> encodeUtf16Le(String s) {
  final out = <int>[0xFF, 0xFE];
  for (final unit in s.codeUnits) {
    out
      ..add(unit & 0xFF)
      ..add((unit >> 8) & 0xFF);
  }
  return out;
}

/// Maps the `Status:` field of `schtasks /Query /FO LIST /V` [output] to a
/// [ServiceStatus]: `Running`→running, `Ready`→installed, `Disabled`→stopped.
ServiceStatus parseState(String output) {
  final m = RegExp(r'Status:\s*(\S+)').firstMatch(output);
  if (m == null) return ServiceStatus.unknown;
  switch (m.group(1)!.toLowerCase()) {
    case 'running':
      return ServiceStatus.running;
    case 'ready':
      return ServiceStatus.installed;
    case 'disabled':
      return ServiceStatus.stopped;
    default:
      return ServiceStatus.unknown;
  }
}

/// Builds the Task Scheduler definition XML for [d].
///
/// System scope runs at boot as `LocalSystem` (`S-1-5-18`) with elevation; user
/// scope runs at logon for [currentUser] with an **S4U** token ("run whether the
/// user is logged on or not") so the daemon runs in a non-interactive session —
/// it shows no console window and keeps running after logoff. The action is
/// wrapped in `cmd.exe /c` so per-service environment can be set inline (Task
/// Scheduler has no per-task environment) and stdout/stderr can be appended to
/// [logPath]. The task has no execution time limit (so the daemon is not killed
/// after the default 72 h) and restarts on failure.
String buildTaskXml(
  ServiceDescriptor d, {
  required String logPath,
  String? currentUser,
}) {
  final system = d.scope == ServiceScope.system;
  final args = _commandLine(d, logPath);

  final triggers = system
      ? '<BootTrigger><Enabled>true</Enabled></BootTrigger>'
      : '<LogonTrigger><Enabled>true</Enabled>'
            '${currentUser == null ? '' : '<UserId>${_xml(currentUser)}</UserId>'}'
            '</LogonTrigger>';

  final principal = system
      ? '<UserId>S-1-5-18</UserId>'
            '<RunLevel>HighestAvailable</RunLevel>'
      : '${currentUser == null ? '' : '<UserId>${_xml(currentUser)}</UserId>'}'
            '<LogonType>S4U</LogonType>'
            '<RunLevel>LeastPrivilege</RunLevel>';

  return '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>${_xml(d.description)}</Description>
  </RegistrationInfo>
  <Triggers>
    $triggers
  </Triggers>
  <Principals>
    <Principal id="Author">
      $principal
    </Principal>
  </Principals>
  <Settings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>9999</Count>
    </RestartOnFailure>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>${_xml(args)}</Arguments>
    </Exec>
  </Actions>
</Task>
''';
}

/// The `cmd.exe` argument string: optional `set <KEY>=<value>` per environment
/// entry, the quoted executable and its arguments, with output appended to
/// [logPath].
String _commandLine(ServiceDescriptor d, String logPath) {
  final parts = <String>[_cmdQuote(d.executablePath)];
  for (final a in d.arguments) {
    parts.add(_cmdQuote(a));
  }
  parts.add('>> ${_cmdQuote(logPath)} 2>&1');
  var line = parts.join(' ');
  if (d.environment.isNotEmpty) {
    final sets = d.environment.entries
        .map((e) => 'set "${e.key}=${e.value}"')
        .join(' && ');
    line = '$sets && $line';
  }
  return '/c "$line"';
}

/// Quotes [s] for a `cmd.exe` command line when it contains whitespace or shell
/// metacharacters.
String _cmdQuote(String s) {
  if (s.isEmpty) return '""';
  return RegExp(r'[\s&|<>^"]').hasMatch(s) ? '"$s"' : s;
}

/// Escapes the five XML metacharacters in [s].
String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Normalizes forward slashes to backslashes (Windows path semantics), so paths
/// composed from [StoragePaths] are consistent regardless of the host the
/// `render`/staging path math runs on.
String _winNorm(String path) => path.replaceAll('/', '\\');

/// The final path segment of [path], splitting on either separator.
String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

/// The directory portion of [path] (everything before the last separator), or
/// the empty string when [path] has no separator.
String _parentDir(String path) {
  final norm = path.replaceAll('/', '\\');
  final i = norm.lastIndexOf('\\');
  return i < 0 ? '' : norm.substring(0, i);
}

/// Case-insensitive, separator-insensitive path equality (Windows semantics).
bool _samePath(String a, String b) =>
    a.replaceAll('/', '\\').toLowerCase() ==
    b.replaceAll('/', '\\').toLowerCase();
