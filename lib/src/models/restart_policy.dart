/// How the init system should restart a service after it exits.
///
/// Each platform driver maps these to its native directive (systemd `Restart=`,
/// launchd `KeepAlive`, Windows SCM failure actions).
enum RestartPolicy {
  /// Always restart, whether the service exited cleanly or not. The default,
  /// matching the behaviour of releases before runtime policy was configurable.
  always,

  /// Restart only when the service exits with a non-zero status.
  onFailure,

  /// Never restart automatically.
  never;

  /// Parses a [RestartPolicy] from its [name] or common aliases
  /// (`on-failure`, `on_failure`).
  ///
  /// Returns `null` when [value] does not name a known policy.
  static RestartPolicy? tryParse(String value) {
    switch (value.trim()) {
      case 'always':
        return RestartPolicy.always;
      case 'onFailure':
      case 'on-failure':
      case 'on_failure':
        return RestartPolicy.onFailure;
      case 'never':
        return RestartPolicy.never;
      default:
        return null;
    }
  }
}
