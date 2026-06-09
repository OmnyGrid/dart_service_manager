import 'package:meta/meta.dart';

import '../errors/service_exception.dart';

/// A single service declaration parsed from a package manifest.
@immutable
class ServiceDefinition {
  /// The service name (the manifest key).
  final String name;

  /// The Dart entrypoint script, relative to the package root.
  final String script;

  /// A human-readable description, when provided in the manifest.
  final String? description;

  /// Extra arguments to pass to the compiled executable.
  final List<String> arguments;

  /// Extra environment variables for the running service.
  final Map<String, String> environment;

  /// Creates a service definition.
  const ServiceDefinition({
    required this.name,
    required this.script,
    this.description,
    this.arguments = const [],
    this.environment = const {},
  });

  @override
  bool operator ==(Object other) =>
      other is ServiceDefinition &&
      other.name == name &&
      other.script == script &&
      other.description == description;

  @override
  int get hashCode => Object.hash(name, script, description);

  @override
  String toString() => 'ServiceDefinition($name -> $script)';
}

/// The set of services declared by a Dart package.
///
/// Built by parsing the `dart_services:` section of a package's `pubspec.yaml`
/// (see `ManifestLoader`). Construction validates the structure and throws a
/// [ServiceManifestException] on any malformed entry, so a [ServiceManifest]
/// instance is always internally consistent.
@immutable
class ServiceManifest {
  /// The owning package name.
  final String packageName;

  /// The declared services, keyed by service name.
  final Map<String, ServiceDefinition> services;

  const ServiceManifest._(this.packageName, this.services);

  /// The declared service names.
  Iterable<String> get serviceNames => services.keys;

  /// Whether the manifest declares a service called [name].
  bool hasService(String name) => services.containsKey(name);

  /// Returns the definition for [name], or throws [ServiceManifestException].
  ServiceDefinition require(String name) {
    final def = services[name];
    if (def == null) {
      throw ServiceManifestException(
        "Package '$packageName' does not declare a service '$name'. "
        'Declared services: ${serviceNames.join(', ')}',
      );
    }
    return def;
  }

  /// Parses and validates a manifest from a decoded `dart_services` [section].
  ///
  /// Accepts the shorthand form `service: bin/foo.dart` and the map form
  /// `service: {script: bin/foo.dart, description: ..., args: [...], env: {...}}`.
  ///
  /// Throws [ServiceManifestException] when the section is empty, a service
  /// name is invalid, or a `script` is missing.
  factory ServiceManifest.parse(
    String packageName,
    Map<dynamic, dynamic>? section,
  ) {
    if (section == null || section.isEmpty) {
      throw ServiceManifestException(
        "Package '$packageName' declares no services. Add a 'dart_services:' "
        'section to its pubspec.yaml.',
      );
    }
    final services = <String, ServiceDefinition>{};
    section.forEach((key, value) {
      final name = key.toString();
      if (!_validName.hasMatch(name)) {
        throw ServiceManifestException(
          "Invalid service name '$name' in package '$packageName'; names must "
          r'match [A-Za-z0-9_-].',
        );
      }
      services[name] = _parseEntry(packageName, name, value);
    });
    return ServiceManifest._(packageName, Map.unmodifiable(services));
  }

  static ServiceDefinition _parseEntry(
    String packageName,
    String name,
    Object? value,
  ) {
    if (value is String) {
      return ServiceDefinition(name: name, script: _requireScript(value, name));
    }
    if (value is Map) {
      final script = value['script'];
      if (script is! String || script.trim().isEmpty) {
        throw ServiceManifestException(
          "Service '$name' in package '$packageName' is missing a 'script'.",
        );
      }
      return ServiceDefinition(
        name: name,
        script: _requireScript(script, name),
        description: value['description']?.toString(),
        arguments: _stringList(value['args'], packageName, name, 'args'),
        environment: _stringMap(value['env'], packageName, name, 'env'),
      );
    }
    throw ServiceManifestException(
      "Service '$name' in package '$packageName' must be a script path or a "
      'map with a script field.',
    );
  }

  static String _requireScript(String script, String name) {
    final trimmed = script.trim();
    if (trimmed.isEmpty) {
      throw ServiceManifestException("Service '$name' has an empty script.");
    }
    return trimmed;
  }

  static List<String> _stringList(
    Object? value,
    String pkg,
    String name,
    String field,
  ) {
    if (value == null) return const [];
    if (value is List) {
      return value.map((e) => e.toString()).toList(growable: false);
    }
    throw ServiceManifestException(
      "Field '$field' of service '$name' in '$pkg' must be a list.",
    );
  }

  static Map<String, String> _stringMap(
    Object? value,
    String pkg,
    String name,
    String field,
  ) {
    if (value == null) return const {};
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    throw ServiceManifestException(
      "Field '$field' of service '$name' in '$pkg' must be a map.",
    );
  }

  static final RegExp _validName = RegExp(r'^[A-Za-z0-9_-]+$');
}
