import 'dart:io';

import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../process/process_runner.dart';
import '../process/system_process_runner.dart';
import 'linux_systemd_driver.dart';
import 'macos_launchd_driver.dart';
import 'platform_service_driver.dart';
import 'windows_service_driver.dart';

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
  }) => forOperatingSystem(
    Platform.operatingSystem,
    processRunner: processRunner,
    logger: logger,
  );

  /// Returns a driver for the given [operatingSystem] identifier (the same
  /// values as `Platform.operatingSystem`: `linux`, `macos`, `windows`).
  ///
  /// Throws [PlatformNotSupportedException] for any other value.
  static PlatformServiceDriver forOperatingSystem(
    String operatingSystem, {
    ProcessRunner processRunner = const SystemProcessRunner(),
    ServiceLogger logger = const SilentServiceLogger(),
  }) {
    switch (operatingSystem) {
      case 'linux':
        return LinuxSystemdDriver(processRunner: processRunner, logger: logger);
      case 'macos':
        return MacOsLaunchdDriver(processRunner: processRunner, logger: logger);
      case 'windows':
        return WindowsServiceDriver(
          processRunner: processRunner,
          logger: logger,
        );
      default:
        throw PlatformNotSupportedException(
          'dart_service_manager does not support "$operatingSystem". Supported '
          'platforms: linux, macos, windows.',
        );
    }
  }
}
