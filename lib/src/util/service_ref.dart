import 'package:meta/meta.dart';

import '../errors/service_exception.dart';

/// A parsed CLI service reference of the form `package` or `package:service`.
///
/// A bare `package` (no [service]) targets every service of the package; a
/// `package:service` targets exactly one.
@immutable
class ServiceRef {
  /// The package name component.
  final String package;

  /// The service name component, or `null` when the whole package is targeted.
  final String? service;

  /// Creates a service reference.
  const ServiceRef(this.package, [this.service]);

  /// Whether the reference targets the whole package (no specific service).
  bool get isPackageWide => service == null;

  /// Parses a `package` or `package:service` [input].
  ///
  /// Throws [ServiceManifestException] when [input] is empty, has an empty
  /// component, or contains more than one `:` separator.
  factory ServiceRef.parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const ServiceManifestException('Empty service reference.');
    }
    final parts = trimmed.split(':');
    if (parts.length > 2) {
      throw ServiceManifestException(
        "Invalid reference '$input'; expected 'package' or 'package:service'.",
      );
    }
    final package = parts[0].trim();
    if (package.isEmpty) {
      throw ServiceManifestException(
        "Invalid reference '$input'; empty package.",
      );
    }
    if (parts.length == 1) return ServiceRef(package);
    final service = parts[1].trim();
    if (service.isEmpty) {
      throw ServiceManifestException(
        "Invalid reference '$input'; empty service.",
      );
    }
    return ServiceRef(package, service);
  }

  @override
  bool operator ==(Object other) =>
      other is ServiceRef &&
      other.package == package &&
      other.service == service;

  @override
  int get hashCode => Object.hash(package, service);

  @override
  String toString() => service == null ? package : '$package:$service';
}
