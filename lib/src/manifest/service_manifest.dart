import 'package:meta/meta.dart';

import '../errors/service_exception.dart';
import '../models/restart_policy.dart';

/// A single service declaration parsed from a package manifest.
///
/// A definition references **either** a Dart [script] to compile (the common
/// case) **or** a pre-built [executable] to install as-is — exactly one is set.
@immutable
class ServiceDefinition {
  /// The service name (the manifest key).
  final String name;

  /// The Dart entrypoint script (relative to the package root) to compile, or
  /// `null` when [executable] is used instead.
  final String? script;

  /// A pre-built native executable to install as-is (relative to the package
  /// root or absolute), or `null` when [script] is compiled instead.
  final String? executable;

  /// A human-readable description, when provided in the manifest.
  final String? description;

  /// Extra arguments to pass to the executable.
  final List<String> arguments;

  /// Extra environment variables for the running service.
  final Map<String, String> environment;

  /// The working directory the service runs in, when set.
  final String? workingDirectory;

  /// How the init system restarts the service after it exits.
  final RestartPolicy restart;

  /// How long to wait between restarts.
  final Duration restartDelay;

  /// Whether the service starts automatically at boot/login.
  final bool autoStart;

  /// Graceful-stop timeout, when set.
  final Duration? stopTimeout;

  /// Path to an environment file to load, when set.
  final String? environmentFile;

  /// Creates a service definition.
  const ServiceDefinition({
    required this.name,
    this.script,
    this.executable,
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

  /// Whether this service is backed by a pre-built [executable] (so it needs no
  /// compilation).
  bool get isPrebuilt => executable != null;

  @override
  bool operator ==(Object other) =>
      other is ServiceDefinition &&
      other.name == name &&
      other.script == script &&
      other.executable == executable &&
      other.description == description;

  @override
  int get hashCode => Object.hash(name, script, executable, description);

  @override
  String toString() => 'ServiceDefinition($name -> ${executable ?? script})';
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
  /// `service: {script|executable: ..., description, args, env,
  /// workingDirectory, restart, restartDelay, autoStart, stopTimeout, envFile}`.
  ///
  /// Throws [ServiceManifestException] when the section is empty, a service
  /// name is invalid, neither/both of `script`/`executable` are given, or a
  /// typed field has a bad value.
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
      return ServiceDefinition(name: name, script: _requirePath(value, name));
    }
    if (value is Map) {
      final script = value['script'];
      final executable = value['executable'];
      final hasScript = script != null;
      final hasExecutable = executable != null;
      if (hasScript == hasExecutable) {
        throw ServiceManifestException(
          "Service '$name' in package '$packageName' must set exactly one of "
          "'script' or 'executable'.",
        );
      }
      return ServiceDefinition(
        name: name,
        script: hasScript ? _requireStringField(script, name, 'script') : null,
        executable: hasExecutable
            ? _requireStringField(executable, name, 'executable')
            : null,
        description: value['description']?.toString(),
        arguments: _stringList(value['args'], packageName, name, 'args'),
        environment: _stringMap(value['env'], packageName, name, 'env'),
        workingDirectory: value['workingDirectory']?.toString(),
        restart: _parseRestart(value['restart'], packageName, name),
        restartDelay: _parseSeconds(
          value['restartDelay'],
          packageName,
          name,
          'restartDelay',
          const Duration(seconds: 5),
        ),
        autoStart: _parseBool(value['autoStart'], packageName, name, true),
        stopTimeout: value['stopTimeout'] == null
            ? null
            : _parseSeconds(
                value['stopTimeout'],
                packageName,
                name,
                'stopTimeout',
                Duration.zero,
              ),
        environmentFile: value['envFile']?.toString(),
      );
    }
    throw ServiceManifestException(
      "Service '$name' in package '$packageName' must be a script path or a "
      'map with a script/executable field.',
    );
  }

  static String _requirePath(String value, String name) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ServiceManifestException("Service '$name' has an empty script.");
    }
    return trimmed;
  }

  static String _requireStringField(Object? value, String name, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw ServiceManifestException(
        "Field '$field' of service '$name' must be a non-empty string.",
      );
    }
    return value.trim();
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

  static RestartPolicy _parseRestart(Object? value, String pkg, String name) {
    if (value == null) return RestartPolicy.always;
    final parsed = RestartPolicy.tryParse(value.toString());
    if (parsed == null) {
      throw ServiceManifestException(
        "Field 'restart' of service '$name' in '$pkg' must be one of "
        'always, on-failure, never.',
      );
    }
    return parsed;
  }

  static bool _parseBool(
    Object? value,
    String pkg,
    String name,
    bool fallback,
  ) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final s = value.toString().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
    throw ServiceManifestException(
      "Field 'autoStart' of service '$name' in '$pkg' must be a boolean.",
    );
  }

  static Duration _parseSeconds(
    Object? value,
    String pkg,
    String name,
    String field,
    Duration fallback,
  ) {
    if (value == null) return fallback;
    final seconds = value is int ? value : int.tryParse(value.toString());
    if (seconds == null || seconds < 0) {
      throw ServiceManifestException(
        "Field '$field' of service '$name' in '$pkg' must be a non-negative "
        'integer number of seconds.',
      );
    }
    return Duration(seconds: seconds);
  }

  static final RegExp _validName = RegExp(r'^[A-Za-z0-9_-]+$');
}
