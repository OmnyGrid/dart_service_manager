/// Declare services in a Dart package, compile them to native executables, and
/// install and manage them as native operating-system services on Linux
/// (systemd), macOS (launchd) and Windows (SCM).
///
/// The library-first API is centred on [DartServiceManager]; the `dart-service`
/// CLI is a thin wrapper over it. See the README for an end-to-end guide.
library;

export 'src/version.dart';

// Manager (public facade).
export 'src/manager/dart_service_manager.dart';

// Models.
export 'src/models/dart_package_service.dart';
export 'src/models/restart_policy.dart';
export 'src/models/service_descriptor.dart';
export 'src/models/service_install_config.dart';
export 'src/models/service_scope.dart';
export 'src/models/service_status.dart';

// Manifest.
export 'src/manifest/manifest_loader.dart';
export 'src/manifest/package_resolver.dart';
export 'src/manifest/service_manifest.dart';

// Compiler.
export 'src/compiler/service_compiler.dart';

// Registry.
export 'src/registry/json_service_registry.dart';
export 'src/registry/registry_entry.dart';
export 'src/registry/service_registry.dart';
export 'src/registry/storage_paths.dart';

// Platform abstraction.
export 'src/drivers/linux_systemd_driver.dart';
export 'src/drivers/macos_launchd_driver.dart';
export 'src/drivers/platform_service_driver.dart';
export 'src/drivers/service_driver_factory.dart';
export 'src/drivers/windows_service_driver.dart';

// Process abstraction.
export 'src/process/privilege_checker.dart';
export 'src/process/process_runner.dart';
export 'src/process/system_process_runner.dart';

// Logging.
export 'src/logging/log_level.dart';
export 'src/logging/service_logger.dart';

// Errors.
export 'src/errors/error_codes.dart';
export 'src/errors/service_exception.dart';
