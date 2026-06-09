import 'package:meta/meta.dart';

import 'service_scope.dart';

/// The inputs required to install a single service.
///
/// Produced by resolving a package manifest entry against the package root and
/// consumed by `DartServiceManager.install`. [scriptPath] is the Dart
/// entrypoint to compile; everything needed to name and describe the resulting
/// OS service is carried alongside it.
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

  /// Creates an install configuration.
  const ServiceInstallConfig({
    required this.packageName,
    required this.serviceName,
    required this.scriptPath,
    this.scope = ServiceScope.user,
    this.description,
    this.arguments = const [],
    this.environment = const {},
  });

  /// Returns a copy with selected fields replaced.
  ServiceInstallConfig copyWith({String? scriptPath, ServiceScope? scope}) =>
      ServiceInstallConfig(
        packageName: packageName,
        serviceName: serviceName,
        scriptPath: scriptPath ?? this.scriptPath,
        scope: scope ?? this.scope,
        description: description,
        arguments: arguments,
        environment: environment,
      );

  @override
  String toString() =>
      'ServiceInstallConfig($packageName:$serviceName, $scriptPath, '
      '${scope.name})';
}
