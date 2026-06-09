import 'package:meta/meta.dart';

import 'restart_policy.dart';
import 'service_scope.dart';

/// The inputs required to install a single service.
///
/// Produced by resolving a package manifest entry against the package root and
/// consumed by `DartServiceManager.install`. [scriptPath] is the Dart
/// entrypoint to compile; everything needed to name, describe and configure the
/// resulting OS service is carried alongside it.
@immutable
class ServiceInstallConfig {
  /// The name of the Dart package declaring the service.
  final String packageName;

  /// The service name as declared in the manifest.
  final String serviceName;

  /// The Dart entrypoint script, absolute or relative to the package root.
  final String scriptPath;

  /// The privilege scope to install under. Defaults to [ServiceScope.user].
  final ServiceScope scope;

  /// A human-readable description recorded in the generated OS service unit.
  ///
  /// When omitted, drivers synthesise one from the package and service names.
  final String? description;

  /// Extra arguments passed to the compiled executable when the service runs.
  final List<String> arguments;

  /// Extra environment variables set for the running service process.
  final Map<String, String> environment;

  /// The working directory the service runs in (defaults to the executable's
  /// directory).
  final String? workingDirectory;

  /// How the init system restarts the service after it exits.
  final RestartPolicy restart;

  /// How long to wait between restarts.
  final Duration restartDelay;

  /// Whether the service starts automatically at boot/login.
  final bool autoStart;

  /// Graceful-stop timeout before the init system kills the service.
  final Duration? stopTimeout;

  /// Path to an environment file to load (systemd `EnvironmentFile=`).
  final String? environmentFile;

  /// Creates an install configuration.
  const ServiceInstallConfig({
    required this.packageName,
    required this.serviceName,
    required this.scriptPath,
    this.scope = ServiceScope.user,
    this.description,
    this.arguments = const [],
    this.environment = const {},
    this.workingDirectory,
    this.restart = RestartPolicy.always,
    this.restartDelay = const Duration(seconds: 5),
    this.autoStart = true,
    this.stopTimeout,
    this.environmentFile,
  });

  /// Returns a copy with selected fields replaced.
  ServiceInstallConfig copyWith({
    String? scriptPath,
    ServiceScope? scope,
    RestartPolicy? restart,
    bool? autoStart,
  }) => ServiceInstallConfig(
    packageName: packageName,
    serviceName: serviceName,
    scriptPath: scriptPath ?? this.scriptPath,
    scope: scope ?? this.scope,
    description: description,
    arguments: arguments,
    environment: environment,
    workingDirectory: workingDirectory,
    restart: restart ?? this.restart,
    restartDelay: restartDelay,
    autoStart: autoStart ?? this.autoStart,
    stopTimeout: stopTimeout,
    environmentFile: environmentFile,
  );

  @override
  String toString() =>
      'ServiceInstallConfig($packageName:$serviceName, $scriptPath, '
      '${scope.name})';
}
