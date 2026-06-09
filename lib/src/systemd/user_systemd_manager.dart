import 'dart:io';

import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../process/process_runner.dart';
import '../process/system_process_runner.dart';
import 'user_systemd_status.dart';

/// Detects, configures and validates the current user's systemd environment so
/// **user-level** services can be installed, enabled, started, and kept running
/// after logout and across reboots.
///
/// This solves the common Linux failure where `systemctl --user …` cannot reach
/// the per-user bus (`Failed to connect to bus: …`) or where services do not
/// persist because *lingering* is not enabled. It is **Linux only**,
/// **idempotent**, and **never assumes root** — it attempts a non-interactive
/// `sudo -n loginctl enable-linger`, and if that is not permitted it returns an
/// actionable warning with the exact command to run.
///
/// All external commands go through an injected [ProcessRunner], so the whole
/// flow is unit-testable without a real systemd. Works across systemd
/// distributions (Debian, Ubuntu, Fedora, RHEL, Rocky, AlmaLinux, Arch, …),
/// which all expose `id`, `loginctl`, `systemctl` and `/run/user/<uid>`.
///
/// ```dart
/// final status = await UserSystemdManager().ensurePersistentUserSystemd();
/// if (!status.ready) {
///   status.warnings.forEach(stderr.writeln);
/// }
/// ```
final class UserSystemdManager {
  /// Runs the probe/configuration commands.
  final ProcessRunner runner;

  /// Environment used to read `XDG_RUNTIME_DIR` (defaults to the process
  /// environment; overridable for testing).
  final Map<String, String> environment;

  /// The operating-system identifier (`Platform.operatingSystem`-compatible);
  /// overridable for testing.
  final String operatingSystem;

  /// Diagnostic logger.
  final ServiceLogger logger;

  /// The `systemctl` executable name or path.
  final String systemctlPath;

  /// The `loginctl` executable name or path.
  final String loginctlPath;

  /// Creates a user-systemd manager.
  UserSystemdManager({
    this.runner = const SystemProcessRunner(),
    Map<String, String>? environment,
    String? operatingSystem,
    this.logger = const SilentServiceLogger(),
    this.systemctlPath = 'systemctl',
    this.loginctlPath = 'loginctl',
  }) : environment = environment ?? Platform.environment,
       operatingSystem = operatingSystem ?? Platform.operatingSystem;

  /// The known `systemctl` user-bus connection failures, in priority order.
  static const List<String> _busFailures = [
    'Failed to connect to bus: No medium found',
    'Failed to connect to bus: No such file or directory',
    'Failed to connect to bus: Connection refused',
    'Failed to connect to bus: Permission denied',
  ];

  /// Detects the current user's systemd environment, enabling lingering when
  /// possible, and returns a detailed [UserSystemdStatus].
  ///
  /// When [enableLinger] is `true` (the default) and lingering is off, it runs
  /// `sudo -n loginctl enable-linger <user>`; if that fails it records an
  /// actionable warning instead of throwing. The method is idempotent — when
  /// the environment is already correct it issues no configuration commands.
  ///
  /// Throws [PlatformNotSupportedException] when not running on Linux.
  Future<UserSystemdStatus> ensurePersistentUserSystemd({
    bool enableLinger = true,
  }) async {
    if (operatingSystem != 'linux') {
      throw PlatformNotSupportedException(
        'Persistent user systemd is a Linux-only feature (running on '
        '$operatingSystem).',
      );
    }

    final diagnostics = <String>[];
    final warnings = <String>[];

    final hasSystemctl = await _commandExists(systemctlPath);
    final hasLoginctl = await _commandExists(loginctlPath);
    diagnostics.add('systemctl: ${hasSystemctl ? 'found' : 'missing'}');
    diagnostics.add('loginctl: ${hasLoginctl ? 'found' : 'missing'}');
    if (!hasSystemctl) {
      warnings.add(
        'systemctl not found — this system does not appear to use systemd, so '
        'user services cannot be managed here.',
      );
    }
    if (!hasLoginctl) {
      warnings.add(
        'loginctl not found — cannot check or enable user lingering, so user '
        'services may not persist after logout.',
      );
    }

    final username = await _username();
    final uid = await _uid();
    diagnostics.add('user: $username (uid $uid)');

    // Lingering.
    var lingerEnabled = false;
    if (hasLoginctl) {
      lingerEnabled = await _lingerEnabled(username);
      diagnostics.add('linger: ${lingerEnabled ? 'enabled' : 'disabled'}');
      if (!lingerEnabled && enableLinger) {
        if (await _enableLinger(username)) {
          lingerEnabled = true;
          diagnostics.add('linger: enabled via sudo loginctl enable-linger');
        } else {
          diagnostics.add('linger: could not be enabled automatically');
          warnings.add(
            'User lingering is not enabled, so services will stop at logout '
            'and not start at boot. Enable it with: '
            'sudo loginctl enable-linger $username',
          );
        }
      }
    }

    // Runtime directory. The per-user bus lives at /run/user/<uid>; an
    // inherited XDG_RUNTIME_DIR that points at a *different* uid (common under
    // sudo/su or service contexts) would send us to another user's bus and
    // fail with "Permission denied", so it is overridden.
    final canonicalRuntime = '/run/user/$uid';
    final inheritedRuntime = environment['XDG_RUNTIME_DIR'];
    final String runtimeDirectory;
    if (inheritedRuntime == null ||
        inheritedRuntime.isEmpty ||
        inheritedRuntime == canonicalRuntime) {
      runtimeDirectory = inheritedRuntime?.isNotEmpty == true
          ? inheritedRuntime!
          : canonicalRuntime;
      diagnostics.add('XDG_RUNTIME_DIR: $runtimeDirectory');
    } else {
      runtimeDirectory = canonicalRuntime;
      diagnostics.add(
        'XDG_RUNTIME_DIR: $canonicalRuntime '
        '(overrode inherited $inheritedRuntime — wrong user)',
      );
      warnings.add(
        'Inherited XDG_RUNTIME_DIR ($inheritedRuntime) belongs to a different '
        'user than $username (uid $uid); using $canonicalRuntime instead. This '
        'usually means the environment came from another user via sudo/su — '
        'run directly as $username for the user bus to work.',
      );
    }

    // User-bus validation.
    var userBusAvailable = false;
    if (hasSystemctl) {
      final result = await runner.run(
        systemctlPath,
        ['--user', 'status'],
        environment: {'XDG_RUNTIME_DIR': runtimeDirectory},
      );
      final busError = _busError(result.stderr);
      userBusAvailable = busError == null;
      if (busError == null) {
        diagnostics.add('user bus: reachable');
      } else {
        diagnostics.add('user bus: $busError');
        if (busError.contains('Permission denied')) {
          warnings.add(
            'Cannot reach the per-user systemd bus (XDG_RUNTIME_DIR='
            '$runtimeDirectory): $busError. The bus socket is owned by '
            '$username (uid $uid) — make sure the install is actually running '
            'as $username (not via sudo/su from another user) and that a login '
            'session or lingering is active.',
          );
        } else {
          warnings.add(
            'Cannot reach the per-user systemd bus (XDG_RUNTIME_DIR='
            '$runtimeDirectory): $busError. Ensure you have an active login '
            'session, or enable lingering '
            '(sudo loginctl enable-linger $username) and reconnect.',
          );
        }
      }
    }

    final status = UserSystemdStatus(
      username: username,
      uid: uid,
      lingerEnabled: lingerEnabled,
      userBusAvailable: userBusAvailable,
      systemctlUserAvailable: hasSystemctl,
      runtimeDirectory: runtimeDirectory,
      diagnostics: diagnostics,
      warnings: warnings,
    );
    for (final d in diagnostics) {
      logger.debug('user-systemd: $d');
    }
    for (final w in warnings) {
      logger.warning(w);
    }
    return status;
  }

  /// Resolves the user's runtime directory for `systemctl --user`.
  ///
  /// Returns `/run/user/<uid>` for the current uid, honouring an inherited
  /// `XDG_RUNTIME_DIR` only when it already matches that path. An inherited
  /// value pointing at another user's runtime dir is ignored (it would route
  /// to the wrong bus).
  Future<String> resolveRuntimeDirectory() => _runtimeDirectoryFor(_uid());

  Future<String> _runtimeDirectoryFor(Future<int> uidFuture) async {
    final uid = await uidFuture;
    final canonical = '/run/user/$uid';
    final fromEnv = environment['XDG_RUNTIME_DIR'];
    return (fromEnv == canonical) ? fromEnv! : canonical;
  }

  /// Returns the first matching known bus failure (or any line containing the
  /// generic prefix), or `null` when the bus is reachable.
  String? _busError(String stderr) {
    for (final marker in _busFailures) {
      if (stderr.contains(marker)) return marker;
    }
    if (stderr.contains('Failed to connect to bus')) {
      return stderr
          .split('\n')
          .firstWhere(
            (line) => line.contains('Failed to connect to bus'),
            orElse: () => 'Failed to connect to bus',
          )
          .trim();
    }
    return null;
  }

  Future<bool> _commandExists(String name) async {
    // POSIX `command -v` is available on every systemd distribution's shell.
    final result = await runner.run('sh', ['-c', 'command -v $name']);
    return result.succeeded;
  }

  Future<String> _username() async {
    final result = await runner.run('id', ['-un']);
    final name = result.stdout.trim();
    return name.isNotEmpty ? name : (environment['USER'] ?? 'unknown');
  }

  Future<int> _uid() async {
    final result = await runner.run('id', ['-u']);
    return int.tryParse(result.stdout.trim()) ??
        int.tryParse(environment['SUDO_UID'] ?? '') ??
        0;
  }

  Future<bool> _lingerEnabled(String username) async {
    final result = await runner.run(loginctlPath, [
      'show-user',
      username,
      '--property=Linger',
    ]);
    return result.stdout.contains('Linger=yes');
  }

  Future<bool> _enableLinger(String username) async {
    // `-n` keeps sudo non-interactive: it never blocks waiting for a password.
    final result = await runner.run('sudo', [
      '-n',
      'loginctl',
      'enable-linger',
      username,
    ]);
    return result.succeeded;
  }
}
