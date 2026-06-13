import 'dart:io';

import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../process/process_runner.dart';
import '../process/system_process_runner.dart';
import '../registry/storage_paths.dart';
import '../systemd/user_systemd_manager.dart';
import 'linux_systemd_driver.dart';
import 'macos_launchd_driver.dart';
import 'platform_service_driver.dart';
import 'windows_service_backend.dart';
import 'windows_service_driver.dart';
import 'windows_task_scheduler_driver.dart';

/// Selects and constructs the [PlatformServiceDriver] appropriate for a host.
final class ServiceDriverFactory {
  const ServiceDriverFactory._();

  /// Returns a driver for the current operating system, wiring in
  /// [processRunner] and [logger].
  ///
  /// Throws [PlatformNotSupportedException] on unsupported platforms.
  static PlatformServiceDriver forCurrentPlatform({
    ProcessRunner processRunner = const SystemProcessRunner(),
    ServiceLogger logger = const SilentServiceLogger(),
    WindowsServiceBackend windowsBackend =
        WindowsServiceBackend.serviceControlManager,
    StoragePaths? storagePaths,
  }) => forOperatingSystem(
    Platform.operatingSystem,
    processRunner: processRunner,
    logger: logger,
    windowsBackend: windowsBackend,
    storagePaths: storagePaths,
  );

  /// Returns a driver for the given [operatingSystem] identifier (the same
  /// values as `Platform.operatingSystem`: `linux`, `macos`, `windows`).
  ///
  /// On Windows, [windowsBackend] selects the Service Control Manager (default,
  /// for back-compat) or Task Scheduler; the latter uses [storagePaths] to stage
  /// the runtime and locate its log.
  ///
  /// Throws [PlatformNotSupportedException] for any other value.
  static PlatformServiceDriver forOperatingSystem(
    String operatingSystem, {
    ProcessRunner processRunner = const SystemProcessRunner(),
    ServiceLogger logger = const SilentServiceLogger(),
    WindowsServiceBackend windowsBackend =
        WindowsServiceBackend.serviceControlManager,
    StoragePaths? storagePaths,
  }) {
    switch (operatingSystem) {
      case 'linux':
        return LinuxSystemdDriver(
          processRunner: processRunner,
          logger: logger,
          // Auto-configure persistent user systemd (lingering / user bus)
          // before user-scoped installs.
          userSystemd: UserSystemdManager(
            runner: processRunner,
            logger: logger,
          ),
        );
      case 'macos':
        return MacOsLaunchdDriver(processRunner: processRunner, logger: logger);
      case 'windows':
        return switch (windowsBackend) {
          WindowsServiceBackend.serviceControlManager => WindowsServiceDriver(
            processRunner: processRunner,
            logger: logger,
          ),
          WindowsServiceBackend.taskScheduler => WindowsTaskSchedulerDriver(
            processRunner: processRunner,
            logger: logger,
            storagePaths: storagePaths,
          ),
        };
      default:
        throw PlatformNotSupportedException(
          'dart_service_manager does not support "$operatingSystem". Supported '
          'platforms: linux, macos, windows.',
        );
    }
  }
}
