import 'dart:io';

import 'process_runner.dart';
import 'system_process_runner.dart';

/// Determines whether the current process is running with elevated
/// (root / administrator) privileges.
///
/// Used to proactively warn about a scope/privilege mismatch at install time —
/// e.g. running under `sudo` while installing a user-scoped service, or
/// installing a system-scoped service without elevation.
abstract interface class PrivilegeChecker {
  /// Whether the process is running as root (POSIX) or an administrator
  /// (Windows).
  Future<bool> isElevated();
}

/// The production [PrivilegeChecker].
///
/// There is no FFI dependency, so elevation is probed through the same
/// [ProcessRunner] abstraction the rest of the package uses: `id -u` on POSIX
/// (elevated when it prints `0`) and `net session` on Windows (succeeds only
/// for administrators). If `id` cannot be run, it falls back to the `SUDO_UID`
/// environment variable.
final class SystemPrivilegeChecker implements PrivilegeChecker {
  /// The runner used to probe privileges.
  final ProcessRunner runner;

  /// Overrides `Platform.operatingSystem` (testing seam).
  final String? operatingSystemOverride;

  /// Overrides `Platform.environment` (testing seam).
  final Map<String, String>? environmentOverride;

  /// Creates a system privilege checker.
  const SystemPrivilegeChecker({
    this.runner = const SystemProcessRunner(),
    this.operatingSystemOverride,
    this.environmentOverride,
  });

  @override
  Future<bool> isElevated() async {
    final os = operatingSystemOverride ?? Platform.operatingSystem;
    if (os == 'windows') {
      // `net session` enumerates sessions and is only permitted for admins.
      final result = await runner.run('net', ['session']);
      return result.succeeded;
    }
    final result = await runner.run('id', ['-u']);
    if (result.succeeded) return result.stdout.trim() == '0';
    // `id` unavailable — fall back to the sudo-provided environment.
    final env = environmentOverride ?? Platform.environment;
    return env['SUDO_UID'] == '0';
  }
}
