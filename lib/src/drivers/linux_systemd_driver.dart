import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../models/service_descriptor.dart';
import '../models/service_scope.dart';
import '../models/service_status.dart';
import '../process/process_runner.dart';
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

  /// Creates a systemd driver.
  LinuxSystemdDriver({
    required this.processRunner,
    this.logger = const SilentServiceLogger(),
    Map<String, String>? environment,
    this.systemctlPath = 'systemctl',
  }) : environment = environment ?? Platform.environment;

  @override
  String get platform => 'linux';

  @override
  bool get supportsPauseResume => false;

  /// The absolute path of the generated `.service` unit for [service].
  String unitPath(ServiceDescriptor service) =>
      p.join(_unitDirectory(service.scope), '${service.systemName}.service');

  @override
  Future<void> install(ServiceDescriptor service) async {
    final dir = Directory(_unitDirectory(service.scope));
    try {
      dir.createSync(recursive: true);
      File(unitPath(service)).writeAsStringSync(buildUnitFile(service));
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
    await _run(
      ['enable', service.systemName],
      service.scope,
      ServiceInstallationException.new,
    );
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
  @visibleForTesting
  String buildUnitFile(ServiceDescriptor service) {
    final exec = [
      service.executablePath,
      ...service.arguments,
    ].map(_quoteIfNeeded).join(' ');
    final wantedBy = service.scope == ServiceScope.system
        ? 'multi-user.target'
        : 'default.target';
    final buffer = StringBuffer()
      ..writeln('[Unit]')
      ..writeln('Description=${service.description}')
      ..writeln('After=network.target')
      ..writeln()
      ..writeln('[Service]')
      ..writeln('Type=simple')
      ..writeln('ExecStart=$exec')
      ..writeln('WorkingDirectory=${p.dirname(service.executablePath)}')
      ..writeln('Restart=always')
      ..writeln('RestartSec=5');
    service.environment.forEach((k, v) {
      buffer.writeln('Environment="$k=$v"');
    });
    buffer
      ..writeln()
      ..writeln('[Install]')
      ..writeln('WantedBy=$wantedBy');
    return buffer.toString();
  }

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

  Future<ProcessRunResult> _systemctl(List<String> args, ServiceScope scope) {
    final full = scope == ServiceScope.user ? ['--user', ...args] : args;
    return processRunner.run(systemctlPath, full);
  }

  Future<void> _run(
    List<String> args,
    ServiceScope scope,
    ServiceManagerException Function(String, {Object? cause}) onError, {
    bool allowFailure = false,
  }) async {
    final result = await _systemctl(args, scope);
    if (!result.succeeded && !allowFailure) {
      throw onError(
        'systemctl ${args.join(' ')} failed (exit ${result.exitCode}): '
        '${result.stderr.trim()}',
      );
    }
  }

  String _quoteIfNeeded(String value) =>
      value.contains(' ') ? '"$value"' : value;
}
