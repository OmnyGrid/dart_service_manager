/// The lifecycle state of a managed service as reported by the platform driver.
enum ServiceStatus {
  /// The service is installed and known to the OS but not currently running.
  installed,

  /// The service is installed and actively running.
  running,

  /// The service is installed and currently paused (Windows only).
  paused,

  /// The service is installed but has been explicitly stopped.
  stopped,

  /// The service is installed but its last run terminated abnormally.
  failed,

  /// The state could not be determined (e.g. the OS reported nothing usable).
  unknown;

  /// Parses a [ServiceStatus] from its [name], falling back to [unknown].
  static ServiceStatus parse(String value) => ServiceStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => ServiceStatus.unknown,
  );
}
