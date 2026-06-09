import 'package:meta/meta.dart';

import '../models/service_scope.dart';
import '../models/service_status.dart';
import '../util/json.dart';

/// A single installed service as recorded in the manager's own registry.
///
/// The registry is the source of truth for *which* services this tool installed
/// and where their binaries live, independent of OS service discovery. The
/// [status] stored here is the last-known status; live status is always
/// re-queried from the platform driver.
@immutable
class RegistryEntry {
  /// The owning package name.
  final String packageName;

  /// The service name.
  final String serviceName;

  /// The platform the service was installed on (`linux`, `macos`, `windows`).
  final String platform;

  /// The privilege scope the service was installed under.
  final ServiceScope scope;

  /// The absolute path to the compiled native executable.
  final String binaryPath;

  /// When the service was installed (UTC).
  final DateTime installedAt;

  /// The last-known status recorded at install/refresh time.
  final ServiceStatus status;

  /// Creates a registry entry.
  RegistryEntry({
    required this.packageName,
    required this.serviceName,
    required this.platform,
    required this.scope,
    required this.binaryPath,
    required this.installedAt,
    this.status = ServiceStatus.installed,
  });

  /// The fully-qualified `package:service` reference.
  String get qualifiedName => '$packageName:$serviceName';

  /// Returns a copy with selected fields replaced.
  RegistryEntry copyWith({ServiceStatus? status, String? binaryPath}) =>
      RegistryEntry(
        packageName: packageName,
        serviceName: serviceName,
        platform: platform,
        scope: scope,
        binaryPath: binaryPath ?? this.binaryPath,
        installedAt: installedAt,
        status: status ?? this.status,
      );

  /// Encodes the entry as a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'package': packageName,
    'service': serviceName,
    'platform': platform,
    'scope': scope.name,
    'binary': binaryPath,
    'installedAt': installedAt.toUtc().toIso8601String(),
    'status': status.name,
  };

  /// Decodes an entry from [json].
  static RegistryEntry fromJson(Map<String, dynamic> json) => RegistryEntry(
    packageName: Json.requireString(json, 'package'),
    serviceName: Json.requireString(json, 'service'),
    platform: Json.requireString(json, 'platform'),
    scope:
        ServiceScope.tryParse(Json.optString(json, 'scope') ?? 'user') ??
        ServiceScope.user,
    binaryPath: Json.requireString(json, 'binary'),
    installedAt: Json.requireTimestamp(json, 'installedAt'),
    status: ServiceStatus.parse(Json.requireString(json, 'status')),
  );

  @override
  String toString() =>
      'RegistryEntry($qualifiedName, $platform/${scope.name}, ${status.name})';
}
