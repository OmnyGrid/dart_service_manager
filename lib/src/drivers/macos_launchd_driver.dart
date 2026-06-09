import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../models/restart_policy.dart';
import '../models/service_descriptor.dart';
import '../models/service_scope.dart';
import '../models/service_status.dart';
import '../process/process_runner.dart';
import 'permission_classifier.dart';
import 'platform_service_driver.dart';

/// A [PlatformServiceDriver] for macOS that manages services through launchd.
///
/// User-scoped services are installed as LaunchAgents in
/// `~/Library/LaunchAgents`; system-scoped services as LaunchDaemons in
/// `/Library/LaunchDaemons` (requires root). A `.plist` is generated from the
/// [ServiceDescriptor] and loaded with `launchctl`.
///
/// launchd has no pause primitive, so [pause]/[resume] throw
/// [PlatformNotSupportedException].
final class MacOsLaunchdDriver implements PlatformServiceDriver {
  /// The runner used to invoke `launchctl`.
  final ProcessRunner processRunner;

  /// The logger for lifecycle progress.
  final ServiceLogger logger;

  /// The environment used to locate the user's `LaunchAgents` directory.
  final Map<String, String> environment;

  /// The `launchctl` executable name or path.
  final String launchctlPath;

  /// Creates a launchd driver.
  MacOsLaunchdDriver({
    required this.processRunner,
    this.logger = const SilentServiceLogger(),
    Map<String, String>? environment,
    this.launchctlPath = 'launchctl',
  }) : environment = environment ?? Platform.environment;

  @override
  String get platform => 'macos';

  @override
  bool get supportsPauseResume => false;

  @override
  bool get supportsEnvironmentFile => false;

  /// The absolute path of the generated `.plist` for [service].
  String plistPath(ServiceDescriptor service) =>
      p.join(_agentsDirectory(service.scope), '${service.launchdLabel}.plist');

  @override
  Future<void> install(ServiceDescriptor service) async {
    final rendered = render(service); // validates env-file support up front
    final dir = Directory(_agentsDirectory(service.scope));
    try {
      dir.createSync(recursive: true);
      File(plistPath(service)).writeAsStringSync(rendered);
    } on IOException catch (e) {
      throw ServiceInstallationException(
        'Failed to write launchd plist for ${service.qualifiedName}',
        cause: e,
      );
    }
    final result = await processRunner.run(launchctlPath, [
      'load',
      '-w',
      plistPath(service),
    ]);
    if (!result.succeeded) {
      _fail(
        result,
        'launchctl load failed (exit ${result.exitCode}): '
        '${result.stderr.trim()}',
        ServiceInstallationException.new,
      );
    }
    logger.info('Installed launchd service ${service.launchdLabel}');
  }

  @override
  Future<void> uninstall(ServiceDescriptor service) async {
    await processRunner.run(launchctlPath, [
      'unload',
      '-w',
      plistPath(service),
    ]);
    try {
      final file = File(plistPath(service));
      if (file.existsSync()) file.deleteSync();
    } on IOException catch (e) {
      throw ServiceInstallationException(
        'Failed to remove launchd plist for ${service.qualifiedName}',
        cause: e,
      );
    }
    logger.info('Uninstalled launchd service ${service.launchdLabel}');
  }

  @override
  Future<void> start(ServiceDescriptor service) async {
    final result = await processRunner.run(launchctlPath, [
      'start',
      service.launchdLabel,
    ]);
    if (!result.succeeded) {
      _fail(
        result,
        'launchctl start failed (exit ${result.exitCode}): '
        '${result.stderr.trim()}',
        ServiceStartException.new,
      );
    }
  }

  @override
  Future<void> stop(ServiceDescriptor service) async {
    final result = await processRunner.run(launchctlPath, [
      'stop',
      service.launchdLabel,
    ]);
    if (!result.succeeded) {
      _fail(
        result,
        'launchctl stop failed (exit ${result.exitCode}): '
        '${result.stderr.trim()}',
        ServiceStopException.new,
      );
    }
  }

  @override
  Future<void> restart(ServiceDescriptor service) async {
    await stop(service);
    await start(service);
  }

  @override
  Future<void> pause(ServiceDescriptor service) async =>
      throw const PlatformNotSupportedException(
        'launchd does not support pausing services.',
      );

  @override
  Future<void> resume(ServiceDescriptor service) async =>
      throw const PlatformNotSupportedException(
        'launchd does not support resuming services.',
      );

  @override
  Future<ServiceStatus> status(ServiceDescriptor service) async {
    final result = await processRunner.run(launchctlPath, [
      'list',
      service.launchdLabel,
    ]);
    if (!result.succeeded) {
      return File(plistPath(service)).existsSync()
          ? ServiceStatus.stopped
          : ServiceStatus.unknown;
    }
    return _parseListOutput(result.stdout);
  }

  /// Renders the launchd plist for [service].
  ///
  /// Throws [PlatformNotSupportedException] if the descriptor sets an
  /// `environmentFile` (launchd has no native equivalent).
  @override
  String render(ServiceDescriptor service) {
    if (service.environmentFile != null) {
      throw const PlatformNotSupportedException(
        'launchd has no environment-file support; inline environment instead.',
      );
    }
    final args = [service.executablePath, ...service.arguments];
    final workingDir =
        service.workingDirectory ?? p.dirname(service.executablePath);
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
      )
      ..writeln('<plist version="1.0">')
      ..writeln('<dict>')
      ..writeln('  <key>Label</key>')
      ..writeln('  <string>${_xml(service.launchdLabel)}</string>')
      ..writeln('  <key>ProgramArguments</key>')
      ..writeln('  <array>');
    for (final arg in args) {
      buffer.writeln('    <string>${_xml(arg)}</string>');
    }
    buffer
      ..writeln('  </array>')
      ..writeln('  <key>RunAtLoad</key>')
      ..writeln('  ${service.autoStart ? '<true/>' : '<false/>'}')
      ..writeln('  <key>KeepAlive</key>');
    _writeKeepAlive(buffer, service.restart);
    buffer
      ..writeln('  <key>WorkingDirectory</key>')
      ..writeln('  <string>${_xml(workingDir)}</string>');
    // A non-default restart delay maps to the minimum respawn interval; left
    // off at the default so the plist is byte-identical to earlier releases.
    if (service.restartDelay.inSeconds != 5) {
      buffer
        ..writeln('  <key>ThrottleInterval</key>')
        ..writeln('  <integer>${service.restartDelay.inSeconds}</integer>');
    }
    if (service.environment.isNotEmpty) {
      buffer
        ..writeln('  <key>EnvironmentVariables</key>')
        ..writeln('  <dict>');
      service.environment.forEach((k, v) {
        buffer
          ..writeln('    <key>${_xml(k)}</key>')
          ..writeln('    <string>${_xml(v)}</string>');
      });
      buffer.writeln('  </dict>');
    }
    if (service.stopTimeout != null) {
      buffer
        ..writeln('  <key>ExitTimeOut</key>')
        ..writeln('  <integer>${service.stopTimeout!.inSeconds}</integer>');
    }
    buffer
      ..writeln('</dict>')
      ..writeln('</plist>');
    return buffer.toString();
  }

  /// Writes the launchd `KeepAlive` value for [policy]: `<true/>` for always,
  /// a `{SuccessfulExit: false}` dict for on-failure, `<false/>` for never.
  void _writeKeepAlive(StringBuffer buffer, RestartPolicy policy) {
    switch (policy) {
      case RestartPolicy.always:
        buffer.writeln('  <true/>');
      case RestartPolicy.never:
        buffer.writeln('  <false/>');
      case RestartPolicy.onFailure:
        buffer
          ..writeln('  <dict>')
          ..writeln('    <key>SuccessfulExit</key>')
          ..writeln('    <false/>')
          ..writeln('  </dict>');
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

  ServiceStatus _parseListOutput(String output) {
    final pidMatch = RegExp(r'"PID"\s*=\s*(\d+)').firstMatch(output);
    if (pidMatch != null) return ServiceStatus.running;
    final exitMatch = RegExp(
      r'"LastExitStatus"\s*=\s*(\d+)',
    ).firstMatch(output);
    if (exitMatch != null && int.parse(exitMatch.group(1)!) != 0) {
      return ServiceStatus.failed;
    }
    return ServiceStatus.stopped;
  }

  String _agentsDirectory(ServiceScope scope) {
    if (scope == ServiceScope.system) return '/Library/LaunchDaemons';
    final home = environment['HOME'];
    if (home == null || home.isEmpty) {
      throw const ServiceInstallationException('HOME is not set.');
    }
    return p.join(home, 'Library', 'LaunchAgents');
  }

  String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
