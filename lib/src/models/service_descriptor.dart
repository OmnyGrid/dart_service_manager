import 'package:meta/meta.dart';

import 'service_scope.dart';

/// The fully-resolved description of an installed service that platform drivers
/// operate on.
///
/// Unlike [ServiceInstallConfig](service_install_config.dart), which references
/// a Dart *script*, a descriptor references the already-compiled native
/// [executablePath]. Drivers use it to generate unit/plist files and to derive
/// the OS-level service identifier via [systemName] and [launchdLabel].
@immutable
class ServiceDescriptor {
  /// The owning Dart package name.
  final String packageName;

  /// The service name as declared in the manifest.
  final String serviceName;

  /// The absolute path to the compiled native executable.
  final String executablePath;

  /// The privilege scope the service is installed under.
  final ServiceScope scope;

  /// A human-readable description recorded in the OS service definition.
  final String description;

  /// Arguments passed to [executablePath] when the service runs.
  final List<String> arguments;

  /// Environment variables set for the running service process.
  final Map<String, String> environment;

  /// Creates a service descriptor.
  ServiceDescriptor({
    required this.packageName,
    required this.serviceName,
    required this.executablePath,
    this.scope = ServiceScope.user,
    String? description,
    this.arguments = const [],
    this.environment = const {},
  }) : description = description ?? 'Dart service $serviceName ($packageName)';

  /// The OS-neutral service identifier, e.g. `dart_analytics_server_worker`.
  ///
  /// Used as the systemd unit base name and the Windows service name. Package
  /// and service names are sanitised to `[A-Za-z0-9_]`.
  String get systemName =>
      'dart_${_sanitize(packageName)}_${_sanitize(serviceName)}';

  /// The reverse-DNS launchd label, e.g.
  /// `com.dartservices.analytics_server.worker`.
  String get launchdLabel =>
      'com.dartservices.${_sanitize(packageName)}.${_sanitize(serviceName)}';

  /// The fully-qualified `package:service` reference.
  String get qualifiedName => '$packageName:$serviceName';

  static String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

  @override
  String toString() => 'ServiceDescriptor($qualifiedName, ${scope.name})';
}
