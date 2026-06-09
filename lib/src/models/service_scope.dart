/// The privilege scope a service is installed under.
///
/// Drivers install user-scoped services without elevation (systemd
/// `--user` units, launchd LaunchAgents, per-user Windows registration) and
/// system-scoped services into the machine-wide locations that require
/// root/administrator privileges.
enum ServiceScope {
  /// Installed for the current user; runs within that user's session and needs
  /// no elevated privileges. This is the default.
  user,

  /// Installed machine-wide; survives logout and starts at boot, but every
  /// lifecycle operation requires root/administrator privileges.
  system;

  /// Parses a [ServiceScope] from its [name].
  ///
  /// Returns `null` when [value] does not name a known scope.
  static ServiceScope? tryParse(String value) {
    for (final scope in ServiceScope.values) {
      if (scope.name == value) return scope;
    }
    return null;
  }
}
