import '../models/service_descriptor.dart';
import '../models/service_status.dart';

/// The platform-abstraction seam: one implementation per supported init system
/// (systemd, launchd, Windows SCM).
///
/// A driver translates the manager's intent into native service operations and
/// owns the generation of any platform artifacts (unit files, plists). Drivers
/// contain no business logic beyond what the OS requires; orchestration,
/// compilation and the registry live in the layer above.
///
/// Implementations: [LinuxSystemdDriver], [MacOsLaunchdDriver],
/// [WindowsServiceDriver]. Select one for the host with
/// `ServiceDriverFactory.forCurrentPlatform`.
abstract interface class PlatformServiceDriver {
  /// The platform identifier this driver targets (`linux`, `macos`,
  /// `windows`).
  String get platform;

  /// Whether this platform supports true pause/resume of a running service.
  ///
  /// systemd and launchd do not; only the Windows SCM does. When `false`,
  /// [pause] and [resume] throw `PlatformNotSupportedException`.
  bool get supportsPauseResume;

  /// Whether this platform can load environment from a file referenced by
  /// `ServiceDescriptor.environmentFile` (systemd does; launchd and the Windows
  /// SCM do not). When `false`, [install] rejects a descriptor that sets one.
  bool get supportsEnvironmentFile;

  /// Renders the native service definition for [service] as a string (a systemd
  /// unit, a launchd plist, or the `sc` command line) **without** touching the
  /// system — the basis of the CLI `--dry-run`.
  String render(ServiceDescriptor service);

  /// Installs [service]: generates any native definition and registers it with
  /// the OS so it can be started.
  Future<void> install(ServiceDescriptor service);

  /// Uninstalls [service]: stops it if running and removes its native
  /// definition.
  Future<void> uninstall(ServiceDescriptor service);

  /// Starts [service].
  Future<void> start(ServiceDescriptor service);

  /// Stops [service].
  Future<void> stop(ServiceDescriptor service);

  /// Pauses [service]. Throws `PlatformNotSupportedException` when
  /// [supportsPauseResume] is `false`.
  Future<void> pause(ServiceDescriptor service);

  /// Resumes a paused [service]. Throws `PlatformNotSupportedException` when
  /// [supportsPauseResume] is `false`.
  Future<void> resume(ServiceDescriptor service);

  /// Restarts [service].
  Future<void> restart(ServiceDescriptor service);

  /// Queries the current [ServiceStatus] of [service].
  Future<ServiceStatus> status(ServiceDescriptor service);
}
