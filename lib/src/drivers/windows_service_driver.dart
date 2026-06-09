import 'package:meta/meta.dart';

import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../models/restart_policy.dart';
import '../models/service_descriptor.dart';
import '../models/service_status.dart';
import '../process/process_runner.dart';
import 'permission_classifier.dart';
import 'platform_service_driver.dart';

/// A [PlatformServiceDriver] for Windows that manages services through the
/// Service Control Manager via `sc.exe`.
///
/// Windows services are always machine-wide and registering one requires
/// administrator privileges regardless of the requested scope. The SCM
/// supports true pause/resume (`sc pause` / `sc continue`).
///
/// Note: a plain compiled Dart executable does not implement a Windows service
/// control dispatcher, so the SCM may report it as failing to respond to
/// control requests in time. Wrapping the entrypoint in a service host is the
/// supported way to make control signals fully honoured; see the package docs.
final class WindowsServiceDriver implements PlatformServiceDriver {
  /// The runner used to invoke `sc.exe`.
  final ProcessRunner processRunner;

  /// The logger for lifecycle progress.
  final ServiceLogger logger;

  /// The `sc.exe` executable name or path.
  final String scPath;

  /// Creates a Windows SCM driver.
  WindowsServiceDriver({
    required this.processRunner,
    this.logger = const SilentServiceLogger(),
    this.scPath = 'sc.exe',
  });

  @override
  String get platform => 'windows';

  @override
  bool get supportsPauseResume => true;

  @override
  bool get supportsEnvironmentFile => false;

  @override
  Future<void> install(ServiceDescriptor service) async {
    _validate(service);
    final result = await processRunner.run(scPath, _createArgs(service));
    if (!result.succeeded) {
      _fail(
        result,
        'sc create failed (exit ${result.exitCode}): ${_message(result)}',
        ServiceInstallationException.new,
      );
    }
    await processRunner.run(scPath, [
      'description',
      service.systemName,
      service.description,
    ]);
    await _configureFailureActions(service);
    logger.info('Installed Windows service ${service.systemName}');
  }

  /// The argument vector for `sc create`, honouring [ServiceDescriptor.autoStart].
  List<String> _createArgs(ServiceDescriptor service) => [
    'create',
    service.systemName,
    'binPath=',
    buildBinPath(service),
    'start=',
    service.autoStart ? 'auto' : 'demand',
    'DisplayName=',
    service.description,
  ];

  /// Configures SCM failure/restart actions to match the restart policy.
  ///
  /// `always`/`onFailure` → restart after [ServiceDescriptor.restartDelay];
  /// `never` → no actions. (SCM failure actions fire on non-graceful exit, so
  /// `always` and `onFailure` map to the same restart action.)
  Future<void> _configureFailureActions(ServiceDescriptor service) async {
    final actions = service.restart == RestartPolicy.never
        ? ''
        : 'restart/${service.restartDelay.inMilliseconds}';
    await processRunner.run(scPath, [
      'failure',
      service.systemName,
      'reset=',
      '${service.restartDelay.inSeconds}',
      'actions=',
      actions,
    ]);
  }

  void _validate(ServiceDescriptor service) {
    if (service.environmentFile != null) {
      throw const PlatformNotSupportedException(
        'The Windows SCM has no environment-file support; set per-service '
        'environment instead.',
      );
    }
    if (service.workingDirectory != null) {
      logger.warning(
        'Windows SCM has no working-directory setting; '
        '"${service.workingDirectory}" is ignored for ${service.systemName}.',
      );
    }
  }

  @override
  Future<void> uninstall(ServiceDescriptor service) async {
    await processRunner.run(scPath, ['stop', service.systemName]);
    final result = await processRunner.run(scPath, [
      'delete',
      service.systemName,
    ]);
    if (!result.succeeded) {
      _fail(
        result,
        'sc delete failed (exit ${result.exitCode}): ${_message(result)}',
        ServiceInstallationException.new,
      );
    }
    logger.info('Uninstalled Windows service ${service.systemName}');
  }

  @override
  String render(ServiceDescriptor service) {
    _validate(service);
    return '$scPath ${_createArgs(service).join(' ')}';
  }

  @override
  Future<void> start(ServiceDescriptor service) =>
      _control('start', service, ServiceStartException.new);

  @override
  Future<void> stop(ServiceDescriptor service) =>
      _control('stop', service, ServiceStopException.new);

  @override
  Future<void> pause(ServiceDescriptor service) =>
      _control('pause', service, ServiceStartException.new);

  @override
  Future<void> resume(ServiceDescriptor service) =>
      _control('continue', service, ServiceStartException.new);

  @override
  Future<void> restart(ServiceDescriptor service) async {
    await processRunner.run(scPath, ['stop', service.systemName]);
    await start(service);
  }

  @override
  Future<ServiceStatus> status(ServiceDescriptor service) async {
    final result = await processRunner.run(scPath, [
      'query',
      service.systemName,
    ]);
    if (!result.succeeded) return ServiceStatus.unknown;
    return parseState(result.stdout);
  }

  /// Builds the `binPath=` value: the quoted executable followed by arguments.
  @visibleForTesting
  String buildBinPath(ServiceDescriptor service) {
    final exe = '"${service.executablePath}"';
    if (service.arguments.isEmpty) return exe;
    return '$exe ${service.arguments.join(' ')}';
  }

  /// Parses the SCM `STATE` code out of `sc query` [output].
  @visibleForTesting
  ServiceStatus parseState(String output) {
    final match = RegExp(r'STATE\s*:\s*(\d+)').firstMatch(output);
    if (match == null) return ServiceStatus.unknown;
    switch (int.parse(match.group(1)!)) {
      case 1: // SERVICE_STOPPED
        return ServiceStatus.stopped;
      case 2: // SERVICE_START_PENDING
      case 3: // SERVICE_STOP_PENDING
      case 4: // SERVICE_RUNNING
        return ServiceStatus.running;
      case 5: // SERVICE_CONTINUE_PENDING
      case 6: // SERVICE_PAUSE_PENDING
      case 7: // SERVICE_PAUSED
        return ServiceStatus.paused;
      default:
        return ServiceStatus.unknown;
    }
  }

  Future<void> _control(
    String verb,
    ServiceDescriptor service,
    ServiceManagerException Function(String, {Object? cause}) onError,
  ) async {
    final result = await processRunner.run(scPath, [verb, service.systemName]);
    if (!result.succeeded) {
      _fail(
        result,
        'sc $verb failed (exit ${result.exitCode}): ${_message(result)}',
        onError,
      );
    }
  }

  Never _fail(
    ProcessRunResult result,
    String message,
    ServiceManagerException Function(String, {Object? cause}) onError,
  ) {
    if (isPermissionFailure(result)) throw PermissionDeniedException(message);
    throw onError(message);
  }

  String _message(ProcessRunResult result) {
    final err = result.stderr.trim();
    return err.isNotEmpty ? err : result.stdout.trim();
  }
}
