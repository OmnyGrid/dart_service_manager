import 'package:meta/meta.dart';

import '../util/json.dart';
import 'service_status.dart';

/// A service belonging to a Dart package, paired with its current OS status.
///
/// This is the primary value object returned by the listing and query APIs on
/// `DartServiceManager`. Equality is structural so instances are safe to use in
/// sets and test expectations.
@immutable
class DartPackageService {
  /// The name of the Dart package that declared the service.
  final String packageName;

  /// The service name as declared in the package manifest.
  final String serviceName;

  /// The absolute path to the compiled native executable backing the service.
  final String executablePath;

  /// The service's current lifecycle [ServiceStatus].
  final ServiceStatus status;

  /// Creates a package-service descriptor.
  const DartPackageService({
    required this.packageName,
    required this.serviceName,
    required this.executablePath,
    required this.status,
  });

  /// The fully-qualified `package:service` reference for this service.
  String get qualifiedName => '$packageName:$serviceName';

  /// Returns a copy with selected fields replaced.
  DartPackageService copyWith({ServiceStatus? status}) => DartPackageService(
    packageName: packageName,
    serviceName: serviceName,
    executablePath: executablePath,
    status: status ?? this.status,
  );

  /// Encodes this descriptor as a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'package': packageName,
    'service': serviceName,
    'executable': executablePath,
    'status': status.name,
  };

  /// Decodes a descriptor from [json].
  static DartPackageService fromJson(Map<String, dynamic> json) =>
      DartPackageService(
        packageName: Json.requireString(json, 'package'),
        serviceName: Json.requireString(json, 'service'),
        executablePath: Json.requireString(json, 'executable'),
        status: ServiceStatus.parse(Json.requireString(json, 'status')),
      );

  @override
  bool operator ==(Object other) =>
      other is DartPackageService &&
      other.packageName == packageName &&
      other.serviceName == serviceName &&
      other.executablePath == executablePath &&
      other.status == status;

  @override
  int get hashCode =>
      Object.hash(packageName, serviceName, executablePath, status);

  @override
  String toString() =>
      'DartPackageService($qualifiedName, ${status.name}, $executablePath)';
}
