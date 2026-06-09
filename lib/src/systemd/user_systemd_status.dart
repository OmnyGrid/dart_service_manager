import 'package:meta/meta.dart';

/// A snapshot of the current user's systemd environment, produced by
/// `UserSystemdManager.ensurePersistentUserSystemd`.
///
/// It captures everything needed to decide whether user-level services can be
/// installed and will **persist** across logout and reboot:
///
/// * [systemctlUserAvailable] — `systemctl` exists and `--user` can be used.
/// * [userBusAvailable] — the per-user D-Bus/systemd bus is reachable.
/// * [lingerEnabled] — the user lingers, so their systemd instance starts at
///   boot and survives logout.
///
/// [diagnostics] records what was checked (useful at debug level); [warnings]
/// holds actionable messages for problems that could not be fixed
/// automatically.
@immutable
class UserSystemdStatus {
  /// The current user's login name (from `id -un`).
  final String username;

  /// The current user's numeric id (from `id -u`).
  final int uid;

  /// Whether lingering is enabled for [username] (`loginctl enable-linger`).
  ///
  /// Without it the user's systemd instance is torn down at logout and does not
  /// start at boot, so user services do not persist.
  final bool lingerEnabled;

  /// Whether the per-user D-Bus/systemd bus could be reached.
  final bool userBusAvailable;

  /// Whether `systemctl` is present and `systemctl --user` is usable.
  final bool systemctlUserAvailable;

  /// The resolved `XDG_RUNTIME_DIR` (`/run/user/<uid>` when unset).
  final String runtimeDirectory;

  /// An ordered log of what was detected, for debug output.
  final List<String> diagnostics;

  /// Actionable warnings for problems that could not be resolved automatically
  /// (e.g. lingering could not be enabled without a password).
  final List<String> warnings;

  /// Creates a status snapshot. The lists are copied unmodifiable.
  UserSystemdStatus({
    required this.username,
    required this.uid,
    required this.lingerEnabled,
    required this.userBusAvailable,
    required this.systemctlUserAvailable,
    required this.runtimeDirectory,
    List<String> diagnostics = const [],
    List<String> warnings = const [],
  }) : diagnostics = List.unmodifiable(diagnostics),
       warnings = List.unmodifiable(warnings);

  /// Whether the environment is fully configured for persistent user services:
  /// `systemctl --user` works, the user bus is reachable, and lingering is on.
  bool get ready => systemctlUserAvailable && userBusAvailable && lingerEnabled;

  /// Encodes this status as a JSON-compatible map (handy for structured logs).
  Map<String, dynamic> toJson() => {
    'username': username,
    'uid': uid,
    'lingerEnabled': lingerEnabled,
    'userBusAvailable': userBusAvailable,
    'systemctlUserAvailable': systemctlUserAvailable,
    'runtimeDirectory': runtimeDirectory,
    'ready': ready,
    'diagnostics': diagnostics,
    'warnings': warnings,
  };

  @override
  String toString() =>
      'UserSystemdStatus($username/$uid, linger: $lingerEnabled, '
      'bus: $userBusAvailable, systemctl: $systemctlUserAvailable, '
      'ready: $ready)';
}
