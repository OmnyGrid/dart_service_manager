import 'error_codes.dart';

/// Base type for every error raised by `dart_service_manager`.
///
/// The hierarchy is [sealed] so callers can exhaustively pattern-match on the
/// concrete failure modes. Each exception carries a stable, machine-readable
/// [code] (see [ErrorCodes]), a human-readable [message], and an optional
/// [cause] that preserves the underlying error (a process failure, an
/// [IOException], etc.) for diagnostics.
///
/// ```dart
/// try {
///   await manager.start('analytics_server', 'worker');
/// } on ServiceManagerException catch (e) {
///   stderr.writeln('${e.code}: ${e.message}');
/// }
/// ```
sealed class ServiceManagerException implements Exception {
  /// A stable, machine-readable error code from [ErrorCodes].
  final String code;

  /// A human-readable description of what went wrong.
  final String message;

  /// The underlying error that triggered this exception, if any.
  final Object? cause;

  /// Creates a service-manager exception.
  const ServiceManagerException(this.code, this.message, {this.cause});

  @override
  String toString() {
    final base = '$runtimeType($code): $message';
    return cause == null ? base : '$base (cause: $cause)';
  }
}

/// Thrown when a service cannot be installed into the operating system.
final class ServiceInstallationException extends ServiceManagerException {
  /// Creates an installation failure with an optional root [cause].
  const ServiceInstallationException(String message, {Object? cause})
    : super(ErrorCodes.installationFailed, message, cause: cause);
}

/// Thrown when compiling a service entrypoint to a native executable fails.
final class ServiceCompilationException extends ServiceManagerException {
  /// Creates a compilation failure with an optional root [cause].
  const ServiceCompilationException(String message, {Object? cause})
    : super(ErrorCodes.compilationFailed, message, cause: cause);
}

/// Thrown when a service fails to start.
final class ServiceStartException extends ServiceManagerException {
  /// Creates a start failure with an optional root [cause].
  const ServiceStartException(String message, {Object? cause})
    : super(ErrorCodes.startFailed, message, cause: cause);
}

/// Thrown when a service fails to stop.
final class ServiceStopException extends ServiceManagerException {
  /// Creates a stop failure with an optional root [cause].
  const ServiceStopException(String message, {Object? cause})
    : super(ErrorCodes.stopFailed, message, cause: cause);
}

/// Thrown when the on-disk service registry cannot be read, written or parsed.
final class ServiceRegistryException extends ServiceManagerException {
  /// Creates a registry failure with an optional root [cause].
  const ServiceRegistryException(String message, {Object? cause})
    : super(ErrorCodes.registryError, message, cause: cause);
}

/// Thrown when an operation is not supported on the current platform — for
/// example pausing a service under launchd or systemd.
final class PlatformNotSupportedException extends ServiceManagerException {
  /// Creates a platform-not-supported failure with an optional root [cause].
  const PlatformNotSupportedException(String message, {Object? cause})
    : super(ErrorCodes.platformNotSupported, message, cause: cause);
}

/// Thrown when a package or service manifest is missing or malformed.
final class ServiceManifestException extends ServiceManagerException {
  /// Creates a manifest failure with an optional root [cause].
  const ServiceManifestException(String message, {Object? cause})
    : super(ErrorCodes.manifestError, message, cause: cause);
}

/// Thrown when a referenced package, service or registry entry does not exist.
final class ServiceNotFoundException extends ServiceManagerException {
  /// Creates a not-found failure with an optional root [cause].
  const ServiceNotFoundException(String message, {Object? cause})
    : super(ErrorCodes.notFound, message, cause: cause);
}
