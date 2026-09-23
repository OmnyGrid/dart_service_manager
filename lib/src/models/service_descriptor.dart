import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'restart_policy.dart';
import 'service_scope.dart';

/// The fully-resolved description of an installed service that platform drivers
/// operate on.
///
/// Unlike [ServiceInstallConfig](service_install_config.dart), which references
/// a Dart *script*, a descriptor references the already-compiled native
/// [executablePath]. Drivers use it to generate unit/plist files and to derive
/// the OS-level service identifier via [systemName] and [launchdLabel].
///
/// The runtime-policy fields ([restart], [restartDelay], [autoStart],
/// [workingDirectory], [stopTimeout], [environmentFile]) are optional and
/// default to the behaviour of releases before they were configurable, so a
/// descriptor that sets none renders byte-identically to before.
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
  ///
  /// This is the full argument vector: when [scriptPath] is set it is the first
  /// element. See [commandArguments] for the caller's command alone.
  final List<String> arguments;

  /// The Dart script the VM runs, when [executablePath] is the Dart VM and the
  /// script leads [arguments] (a [forCurrentExecutable] install running under
  /// JIT: `dart <script> <command…>`). `null` for an executable that runs the
  /// command directly.
  ///
  /// Recorded separately so a reinstall can rebuild the command without
  /// carrying over the runtime prefix of the process that installed it.
  final String? scriptPath;

  /// Environment variables set for the running service process.
  ///
  /// Prefer [environmentFile] for secrets/paths on platforms that support it
  /// (systemd), so values are not inlined into the unit body.
  final Map<String, String> environment;

  /// The working directory the service runs in. Defaults to the directory
  /// containing [executablePath] when `null`.
  final String? workingDirectory;

  /// How the init system restarts the service after it exits.
  final RestartPolicy restart;

  /// How long to wait between restarts. Defaults to 5 seconds.
  final Duration restartDelay;

  /// Whether the service starts automatically at boot/login. Defaults to `true`.
  final bool autoStart;

  /// How long the init system waits for a graceful stop before killing the
  /// service. `null` uses the platform default.
  final Duration? stopTimeout;

  /// Path to a file of `KEY=value` lines to load into the service environment,
  /// on platforms that support it (systemd `EnvironmentFile=`). Drivers without
  /// support reject a non-null value; check [PlatformServiceDriver.supportsEnvironmentFile].
  final String? environmentFile;

  /// Creates a service descriptor.
  ServiceDescriptor({
    required this.packageName,
    required this.serviceName,
    required this.executablePath,
    this.scope = ServiceScope.user,
    String? description,
    this.arguments = const [],
    String? scriptPath,
    this.environment = const {},
    this.workingDirectory,
    this.restart = RestartPolicy.always,
    this.restartDelay = const Duration(seconds: 5),
    this.autoStart = true,
    this.stopTimeout,
    this.environmentFile,
  }) : description = description ?? 'Dart service $serviceName ($packageName)',
       // Kept only when it actually leads [arguments], so a non-null
       // [scriptPath] always means `arguments.first == scriptPath`.
       scriptPath = arguments.isNotEmpty && arguments.first == scriptPath
           ? scriptPath
           : null;

  /// [arguments] without the leading [scriptPath]: the command the service
  /// runs, independent of the runtime that launches it. Pass this — not
  /// [arguments] — back to [forCurrentExecutable] to re-derive the descriptor.
  List<String> get commandArguments =>
      scriptPath == null ? arguments : arguments.sublist(1);

  /// Creates a descriptor that installs the **currently running executable** as
  /// a service — the "install myself" case used by CLIs that ship as an AOT
  /// binary.
  ///
  /// Resolves `Platform.resolvedExecutable`. When the process is running under
  /// the Dart VM (JIT) rather than an AOT binary, `resolvedExecutable` is the
  /// `dart` tool, so the running script (`Platform.script`) is prepended to
  /// [arguments] — the resulting service runs `dart <script> <args…>`. For an
  /// AOT binary (`dart compile exe`, `dart pub global activate`) the executable
  /// is the binary itself and [arguments] are used as-is.
  ///
  /// [arguments] should be the command alone — for a reinstall, the recorded
  /// [RegistryEntry.arguments] or [commandArguments]. A runtime prefix left in
  /// it by an earlier install (see [resolveSelfExecutable]) is dropped, so
  /// re-derivation never doubles the script or keeps a stale one.
  factory ServiceDescriptor.forCurrentExecutable({
    required String packageName,
    required String serviceName,
    List<String> arguments = const [],
    Map<String, String> environment = const {},
    ServiceScope scope = ServiceScope.user,
    String? description,
    String? workingDirectory,
    RestartPolicy restart = RestartPolicy.always,
    Duration restartDelay = const Duration(seconds: 5),
    bool autoStart = true,
    Duration? stopTimeout,
    String? environmentFile,
  }) {
    final script = Platform.script.isScheme('file')
        ? Platform.script.toFilePath()
        : null;
    final resolved = resolveSelfExecutable(
      resolvedExecutable: Platform.resolvedExecutable,
      script: script,
      arguments: arguments,
    );
    return ServiceDescriptor(
      packageName: packageName,
      serviceName: serviceName,
      executablePath: resolved.executable,
      arguments: resolved.arguments,
      scriptPath: resolved.script,
      environment: environment,
      scope: scope,
      description: description,
      workingDirectory: workingDirectory,
      restart: restart,
      restartDelay: restartDelay,
      autoStart: autoStart,
      stopTimeout: stopTimeout,
      environmentFile: environmentFile,
    );
  }

  /// Computes the `(executable, arguments, script)` triple for "install
  /// myself".
  ///
  /// If [resolvedExecutable] is the Dart VM (`dart`/`dart.exe`) and a [script]
  /// is known, the script is prepended to [arguments] so the service launches
  /// `dart <script> …`, and returned as `script`; otherwise
  /// [resolvedExecutable] is an AOT binary, [arguments] are the command as-is
  /// and `script` is `null`. Exposed for deterministic testing of the
  /// JIT-vs-AOT branch.
  ///
  /// Leading runtime scripts already in [arguments] are dropped first — the
  /// current [script], or any absolute path ending in `.snapshot`, `.dill` or
  /// `.dart` (see [isRuntimeScript]). Arguments recorded by releases before
  /// [scriptPath] existed carry the installing process's script, and it goes
  /// stale when the runtime changes: a later AOT build would run
  /// `<binary> <old snapshot> …`, and an SDK upgrade (which renames the
  /// pub-cache snapshot) would run `dart <new> <old> …`.
  @visibleForTesting
  static ({String executable, List<String> arguments, String? script})
  resolveSelfExecutable({
    required String resolvedExecutable,
    String? script,
    List<String> arguments = const [],
  }) {
    var start = 0;
    while (start < arguments.length &&
        (arguments[start] == script || isRuntimeScript(arguments[start]))) {
      start++;
    }
    final command = arguments.sublist(start);
    // Windows-style parsing accepts both `/` and `\` separators.
    final base = p.windows
        .basenameWithoutExtension(resolvedExecutable)
        .toLowerCase();
    if (base == 'dart' && script != null) {
      return (
        executable: resolvedExecutable,
        arguments: [script, ...command],
        script: script,
      );
    }
    return (executable: resolvedExecutable, arguments: command, script: null);
  }

  /// Whether [argument] looks like a Dart runtime script — an absolute path to
  /// a `.snapshot`, `.dill` or `.dart` file — rather than part of a command.
  @visibleForTesting
  static bool isRuntimeScript(String argument) {
    if (!p.isAbsolute(argument) && !p.windows.isAbsolute(argument)) {
      return false;
    }
    final ext = p.extension(argument).toLowerCase();
    return ext == '.snapshot' || ext == '.dill' || ext == '.dart';
  }

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

  /// Returns a copy with selected fields replaced.
  ServiceDescriptor copyWith({
    String? executablePath,
    ServiceScope? scope,
    String? description,
    List<String>? arguments,
    String? scriptPath,
    Map<String, String>? environment,
    String? workingDirectory,
    RestartPolicy? restart,
    Duration? restartDelay,
    bool? autoStart,
    Duration? stopTimeout,
    String? environmentFile,
  }) => ServiceDescriptor(
    packageName: packageName,
    serviceName: serviceName,
    executablePath: executablePath ?? this.executablePath,
    scope: scope ?? this.scope,
    description: description ?? this.description,
    arguments: arguments ?? this.arguments,
    scriptPath: scriptPath ?? this.scriptPath,
    environment: environment ?? this.environment,
    workingDirectory: workingDirectory ?? this.workingDirectory,
    restart: restart ?? this.restart,
    restartDelay: restartDelay ?? this.restartDelay,
    autoStart: autoStart ?? this.autoStart,
    stopTimeout: stopTimeout ?? this.stopTimeout,
    environmentFile: environmentFile ?? this.environmentFile,
  );

  static String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

  @override
  String toString() => 'ServiceDescriptor($qualifiedName, ${scope.name})';
}
