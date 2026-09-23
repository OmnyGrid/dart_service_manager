import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../models/restart_policy.dart';
import '../models/service_scope.dart';
import '../models/service_status.dart';
import '../util/json.dart';

/// A single installed service as recorded in the manager's own registry.
///
/// The registry is the source of truth for *which* services this tool installed,
/// where their binaries live, and with what arguments/environment/policy —
/// independent of OS service discovery. This lets lifecycle, listing and
/// reconfigure rebuild the full [ServiceDescriptor] without re-reading a
/// manifest. The [status] stored here is the last-known status; live status is
/// always re-queried from the platform driver.
///
/// All fields beyond the original core set are optional on read, so registries
/// written by earlier versions still load (their values default to the
/// pre-policy behaviour).
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

  /// The absolute path to the native executable.
  final String binaryPath;

  /// When the service was installed (UTC).
  final DateTime installedAt;

  /// The last-known status recorded at install/refresh time.
  final ServiceStatus status;

  /// The command the service runs: the arguments after [scriptPath], if any.
  /// Feed these back to [ServiceDescriptor.forCurrentExecutable] on reinstall.
  /// [commandLine] is the full vector passed to [binaryPath].
  final List<String> arguments;

  /// The Dart script [binaryPath] (the Dart VM) runs ahead of [arguments], or
  /// `null` when the binary runs the command directly.
  final String? scriptPath;

  /// Environment variables set for the running service.
  final Map<String, String> environment;

  /// The recorded human-readable description, if any.
  final String? description;

  /// The working directory the service runs in, if overridden.
  final String? workingDirectory;

  /// The restart policy.
  final RestartPolicy restart;

  /// The delay between restarts.
  final Duration restartDelay;

  /// Whether the service starts at boot/login.
  final bool autoStart;

  /// The graceful-stop timeout, if set.
  final Duration? stopTimeout;

  /// The environment file path, if set.
  final String? environmentFile;

  /// Creates a registry entry.
  RegistryEntry({
    required this.packageName,
    required this.serviceName,
    required this.platform,
    required this.scope,
    required this.binaryPath,
    required this.installedAt,
    this.status = ServiceStatus.installed,
    this.arguments = const [],
    this.scriptPath,
    this.environment = const {},
    this.description,
    this.workingDirectory,
    this.restart = RestartPolicy.always,
    this.restartDelay = const Duration(seconds: 5),
    this.autoStart = true,
    this.stopTimeout,
    this.environmentFile,
  });

  /// The fully-qualified `package:service` reference.
  String get qualifiedName => '$packageName:$serviceName';

  /// The full argument vector passed to [binaryPath]: [scriptPath] (when set)
  /// followed by [arguments].
  List<String> get commandLine => [?scriptPath, ...arguments];

  /// Returns a copy with selected fields replaced, preserving everything else.
  RegistryEntry copyWith({ServiceStatus? status, String? binaryPath}) =>
      RegistryEntry(
        packageName: packageName,
        serviceName: serviceName,
        platform: platform,
        scope: scope,
        binaryPath: binaryPath ?? this.binaryPath,
        installedAt: installedAt,
        status: status ?? this.status,
        arguments: arguments,
        scriptPath: scriptPath,
        environment: environment,
        description: description,
        workingDirectory: workingDirectory,
        restart: restart,
        restartDelay: restartDelay,
        autoStart: autoStart,
        stopTimeout: stopTimeout,
        environmentFile: environmentFile,
      );

  /// Encodes the entry as a JSON-compatible map. Empty/default optional fields
  /// are omitted to keep the registry compact.
  Map<String, dynamic> toJson() => {
    'package': packageName,
    'service': serviceName,
    'platform': platform,
    'scope': scope.name,
    'binary': binaryPath,
    'installedAt': installedAt.toUtc().toIso8601String(),
    'status': status.name,
    if (arguments.isNotEmpty) 'args': arguments,
    // Always written (null when absent): its presence marks [arguments] as the
    // command alone, so [fromJson] does not apply the legacy split.
    'script': scriptPath,
    if (environment.isNotEmpty) 'env': environment,
    if (description != null) 'description': description,
    if (workingDirectory != null) 'workingDirectory': workingDirectory,
    'restart': restart.name,
    'restartDelay': restartDelay.inSeconds,
    'autoStart': autoStart,
    if (stopTimeout != null) 'stopTimeout': stopTimeout!.inSeconds,
    if (environmentFile != null) 'environmentFile': environmentFile,
  };

  /// Decodes an entry from [json]. All policy/descriptor fields are optional,
  /// defaulting to the pre-1.1.0 behaviour for back-compatibility.
  ///
  /// Entries written before `script` was recorded kept the script inside
  /// `args`. For those, a Dart VM binary's first argument is split out as
  /// [scriptPath], so [arguments] is the command alone.
  static RegistryEntry fromJson(Map<String, dynamic> json) {
    final binaryPath = Json.requireString(json, 'binary');
    var arguments = _stringList(json['args']);
    var scriptPath = Json.optString(json, 'script');
    if (!json.containsKey('script') &&
        _isDartVm(binaryPath) &&
        arguments.isNotEmpty) {
      scriptPath = arguments.first;
      arguments = arguments.sublist(1);
    }
    return RegistryEntry(
      packageName: Json.requireString(json, 'package'),
      serviceName: Json.requireString(json, 'service'),
      platform: Json.requireString(json, 'platform'),
      scope:
          ServiceScope.tryParse(Json.optString(json, 'scope') ?? 'user') ??
          ServiceScope.user,
      binaryPath: binaryPath,
      installedAt: Json.requireTimestamp(json, 'installedAt'),
      status: ServiceStatus.parse(Json.requireString(json, 'status')),
      arguments: arguments,
      scriptPath: scriptPath,
      environment: _stringMap(json['env']),
      description: Json.optString(json, 'description'),
      workingDirectory: Json.optString(json, 'workingDirectory'),
      restart:
          RestartPolicy.tryParse(Json.optString(json, 'restart') ?? 'always') ??
          RestartPolicy.always,
      restartDelay: Duration(seconds: _intOr(json['restartDelay'], 5)),
      autoStart: json['autoStart'] is bool ? json['autoStart'] as bool : true,
      stopTimeout: json['stopTimeout'] == null
          ? null
          : Duration(seconds: _intOr(json['stopTimeout'], 0)),
      environmentFile: Json.optString(json, 'environmentFile'),
    );
  }

  /// Whether [binaryPath] is the Dart VM, whose first argument is the script.
  /// Parsed Windows-style, which accepts both `/` and `\` separators.
  static bool _isDartVm(String binaryPath) =>
      p.windows.basenameWithoutExtension(binaryPath).toLowerCase() == 'dart';

  static List<String> _stringList(Object? value) => value is List
      ? value.map((e) => e.toString()).toList(growable: false)
      : const [];

  static Map<String, String> _stringMap(Object? value) => value is Map
      ? value.map((k, v) => MapEntry(k.toString(), v.toString()))
      : const {};

  static int _intOr(Object? value, int fallback) => value is int
      ? value
      : (int.tryParse(value?.toString() ?? '') ?? fallback);

  @override
  String toString() =>
      'RegistryEntry($qualifiedName, $platform/${scope.name}, ${status.name})';
}
