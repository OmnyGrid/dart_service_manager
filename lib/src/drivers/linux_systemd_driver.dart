import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../models/restart_policy.dart';
import '../models/service_descriptor.dart';
import '../models/service_scope.dart';
import '../models/service_status.dart';
import '../process/process_runner.dart';
import '../systemd/user_systemd_manager.dart';
import 'permission_classifier.dart';
import 'platform_service_driver.dart';

/// A [PlatformServiceDriver] for Linux that manages services through systemd.
///
/// User-scoped services are written to `~/.config/systemd/user` and driven with
/// `systemctl --user`; system-scoped services go to `/etc/systemd/system` and
/// require root. The `.service` unit is generated from the [ServiceDescriptor].
///
/// systemd has no notion of pausing a unit, so [pause]/[resume] throw
/// [PlatformNotSupportedException].
final class LinuxSystemdDriver implements PlatformServiceDriver {
  /// The runner used to invoke `systemctl`.
  final ProcessRunner processRunner;

  /// The logger for lifecycle progress.
  final ServiceLogger logger;

  /// The environment used to locate user unit directories (`HOME`,
  /// `XDG_CONFIG_HOME`).
  final Map<String, String> environment;

  /// The `systemctl` executable name or path.
  final String systemctlPath;

  /// Ensures the per-user systemd environment is persistent (lingering enabled,
  /// user bus reachable) before user-scoped installs, and supplies the
  /// `XDG_RUNTIME_DIR` used for `systemctl --user` calls.
  ///
  /// When `null`, that handling is skipped and `systemctl --user` runs with the
  /// inherited environment (the pre-1.x behaviour).
  final UserSystemdManager? userSystemd;

  /// Cached resolved `XDG_RUNTIME_DIR` for user-scope `systemctl` calls.
  String? _runtimeDirectory;

  /// Creates a systemd driver.
  LinuxSystemdDriver({
    required this.processRunner,
    this.logger = const SilentServiceLogger(),
    Map<String, String>? environment,
    this.systemctlPath = 'systemctl',
    this.userSystemd,
  }) : environment = environment ?? Platform.environment;

  @override
  String get platform => 'linux';

  @override
  bool get supportsPauseResume => false;

  @override
  bool get supportsEnvironmentFile => true;

  /// The absolute path of the generated `.service` unit for [service].
  String unitPath(ServiceDescriptor service) =>
      p.join(_unitDirectory(service.scope), '${service.systemName}.service');

  @override
  Future<void> install(ServiceDescriptor service) async {
    if (service.scope == ServiceScope.user && userSystemd != null) {
      // Make the user systemd instance persistent (lingering) and validate the
      // user bus before we try to enable/start a --user unit.
      final status = await userSystemd!.ensurePersistentUserSystemd();
      _runtimeDirectory = status.runtimeDirectory;
    }
    final dir = Directory(_unitDirectory(service.scope));
    try {
      dir.createSync(recursive: true);
      File(unitPath(service)).writeAsStringSync(render(service));
    } on IOException catch (e) {
      throw ServiceInstallationException(
        'Failed to write systemd unit for ${service.qualifiedName}',
        cause: e,
      );
    }
    await _run(
      ['daemon-reload'],
      service.scope,
      ServiceInstallationException.new,
    );
    // `enable` creates the boot/login symlink; skip it for non-autostart units.
    if (service.autoStart) {
      await _run(
        ['enable', service.systemName],
        service.scope,
        ServiceInstallationException.new,
      );
    }
    logger.info('Installed systemd unit ${unitPath(service)}');
  }

  @override
  Future<void> uninstall(ServiceDescriptor service) async {
    await _run(
      ['disable', '--now', service.systemName],
      service.scope,
      ServiceInstallationException.new,
      allowFailure: true,
    );
    try {
      final file = File(unitPath(service));
      if (file.existsSync()) file.deleteSync();
    } on IOException catch (e) {
      throw ServiceInstallationException(
        'Failed to remove systemd unit for ${service.qualifiedName}',
        cause: e,
      );
    }
    await _run(
      ['daemon-reload'],
      service.scope,
      ServiceInstallationException.new,
    );
    logger.info('Uninstalled systemd unit ${service.systemName}');
  }

  @override
  Future<void> start(ServiceDescriptor service) => _run(
    ['start', service.systemName],
    service.scope,
    ServiceStartException.new,
  );

  @override
  Future<void> stop(ServiceDescriptor service) => _run(
    ['stop', service.systemName],
    service.scope,
    ServiceStopException.new,
  );

  @override
  Future<void> restart(ServiceDescriptor service) => _run(
    ['restart', service.systemName],
    service.scope,
    ServiceStartException.new,
  );

  @override
  Future<void> pause(ServiceDescriptor service) async =>
      throw const PlatformNotSupportedException(
        'systemd does not support pausing services.',
      );

  @override
  Future<void> resume(ServiceDescriptor service) async =>
      throw const PlatformNotSupportedException(
        'systemd does not support resuming services.',
      );

  @override
  Future<ServiceStatus> status(ServiceDescriptor service) async {
    final result = await _systemctl([
      'is-active',
      service.systemName,
    ], service.scope);
    return _mapStatus(result.stdout.trim(), service);
  }

  /// Renders the systemd unit file for [service].
  @override
  String render(ServiceDescriptor service) {
    final exec = [
      service.executablePath,
      ...service.arguments,
    ].map(_quoteIfNeeded).join(' ');
    final wantedBy = service.scope == ServiceScope.system
        ? 'multi-user.target'
        : 'default.target';
    final workingDir =
        service.workingDirectory ?? p.dirname(service.executablePath);
    final buffer = StringBuffer()
      ..writeln('[Unit]')
      ..writeln('Description=${service.description}')
      ..writeln('After=network.target')
      ..writeln()
      ..writeln('[Service]')
      ..writeln('Type=simple')
      ..writeln('ExecStart=$exec')
      ..writeln('WorkingDirectory=$workingDir')
      ..writeln('Restart=${_restartValue(service.restart)}')
      ..writeln('RestartSec=${service.restartDelay.inSeconds}');
    if (service.stopTimeout != null) {
      buffer.writeln('TimeoutStopSec=${service.stopTimeout!.inSeconds}');
    }
    if (service.environmentFile != null) {
      buffer.writeln('EnvironmentFile=${service.environmentFile}');
    } else {
      service.environment.forEach((k, v) {
        buffer.writeln('Environment="$k=$v"');
      });
    }
    buffer
      ..writeln()
      ..writeln('[Install]')
      ..writeln('WantedBy=$wantedBy');
    return buffer.toString();
  }

  static String _restartValue(RestartPolicy policy) => switch (policy) {
    RestartPolicy.always => 'always',
    RestartPolicy.onFailure => 'on-failure',
    RestartPolicy.never => 'no',
  };

  ServiceStatus _mapStatus(String raw, ServiceDescriptor service) {
    switch (raw) {
      case 'active':
        return ServiceStatus.running;
      case 'activating':
      case 'reloading':
        return ServiceStatus.running;
      case 'failed':
        return ServiceStatus.failed;
      case 'inactive':
      case 'deactivating':
        return File(unitPath(service)).existsSync()
            ? ServiceStatus.stopped
            : ServiceStatus.unknown;
      default:
        return File(unitPath(service)).existsSync()
            ? ServiceStatus.installed
            : ServiceStatus.unknown;
    }
  }

  String _unitDirectory(ServiceScope scope) {
    if (scope == ServiceScope.system) return '/etc/systemd/system';
    final xdg = environment['XDG_CONFIG_HOME'];
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : p.join(_home, '.config');
    return p.join(base, 'systemd', 'user');
  }

  String get _home {
    final home = environment['HOME'];
    if (home == null || home.isEmpty) {
      throw const ServiceInstallationException('HOME is not set.');
    }
    return home;
  }

  Future<ProcessRunResult> _systemctl(
    List<String> args,
    ServiceScope scope,
  ) async {
    if (scope != ServiceScope.user) {
      return processRunner.run(systemctlPath, args);
    }
    return processRunner.run(systemctlPath, [
      '--user',
      ...args,
    ], environment: await _userEnvironment());
  }

  /// The environment for `systemctl --user` calls. When a [userSystemd] manager
  /// is configured, `XDG_RUNTIME_DIR` is resolved (and cached) so the call can
  /// reach the per-user bus even when it is absent from the inherited
  /// environment; otherwise `null` preserves the inherited environment.
  Future<Map<String, String>?> _userEnvironment() async {
    if (userSystemd == null) return null;
    _runtimeDirectory ??= await userSystemd!.resolveRuntimeDirectory();
    return {'XDG_RUNTIME_DIR': _runtimeDirectory!};
  }

  Future<void> _run(
    List<String> args,
    ServiceScope scope,
    ServiceManagerException Function(String, {Object? cause}) onError, {
    bool allowFailure = false,
  }) async {
    final result = await _systemctl(args, scope);
    if (!result.succeeded && !allowFailure) {
      final message =
          'systemctl ${args.join(' ')} failed (exit ${result.exitCode}): '
          '${result.stderr.trim()}';
      if (isPermissionFailure(result)) {
        throw PermissionDeniedException(message);
      }
      throw onError(message);
    }
  }

  String _quoteIfNeeded(String value) =>
      value.contains(' ') ? '"$value"' : value;
}
