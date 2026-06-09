/// Stable, machine-readable error codes attached to every
/// [ServiceManagerException](service_exception.dart).
///
/// Codes are part of the public contract: tools and tests may switch on them,
/// so existing values must never change meaning. Human-readable detail lives in
/// the exception message, not here.
final class ErrorCodes {
  const ErrorCodes._();

  /// A service could not be installed into the operating system.
  static const String installationFailed = 'installation_failed';

  /// `dart compile exe` failed or produced no executable.
  static const String compilationFailed = 'compilation_failed';

  /// A service failed to start.
  static const String startFailed = 'start_failed';

  /// A service failed to stop.
  static const String stopFailed = 'stop_failed';

  /// The on-disk registry could not be read, written or parsed.
  static const String registryError = 'registry_error';

  /// The requested operation is not supported on the current platform.
  static const String platformNotSupported = 'platform_not_supported';

  /// A package or service manifest was missing or malformed.
  static const String manifestError = 'manifest_error';

  /// A referenced package, service or registry entry does not exist.
  static const String notFound = 'not_found';
}
