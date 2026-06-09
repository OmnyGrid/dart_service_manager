import 'dart:io';

import '../compiler/service_compiler.dart';
import '../drivers/platform_service_driver.dart';
import '../drivers/service_driver_factory.dart';
import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../manifest/manifest_loader.dart';
import '../manifest/package_resolver.dart';
import '../models/dart_package_service.dart';
import '../models/service_descriptor.dart';
import '../models/service_scope.dart';
import '../models/service_status.dart';
import '../process/process_runner.dart';
import '../process/system_process_runner.dart';
import '../registry/json_service_registry.dart';
import '../registry/registry_entry.dart';
import '../registry/service_registry.dart';
import '../registry/storage_paths.dart';

/// The public entry point for declaring, compiling, installing and managing
/// Dart-package services as native operating-system services.
///
/// `DartServiceManager` is the single facade the CLI and embedding code use; it
/// orchestrates the [PackageResolver], [ManifestLoader], [ServiceCompiler],
/// [ServiceRegistry] and the platform [PlatformServiceDriver] but contains no
/// platform-specific logic itself. Every collaborator is constructor-injected,
/// so the whole flow can be exercised against fakes.
///
/// Construct one wired for the host with [DartServiceManager.forCurrentPlatform]:
///
/// ```dart
/// final manager = DartServiceManager.forCurrentPlatform();
/// await manager.install('analytics_server');          // all services
/// await manager.start('analytics_server', 'worker');
/// final status = await manager.status('analytics_server', 'worker');
/// ```
class DartServiceManager {
  /// Resolves package names to source directories.
  final PackageResolver resolver;

  /// Loads service manifests from package pubspecs.
  final ManifestLoader manifestLoader;

  /// Compiles service entrypoints to native executables.
  final ServiceCompiler compiler;

  /// The persistent record of installed services.
  final ServiceRegistry registry;

  /// The platform driver that performs native service operations.
  final PlatformServiceDriver driver;

  /// The structured logger.
  final ServiceLogger logger;

  /// Creates a manager from explicit collaborators (used in tests).
  DartServiceManager({
    required this.resolver,
    required this.manifestLoader,
    required this.compiler,
    required this.registry,
    required this.driver,
    this.logger = const SilentServiceLogger(),
  });

  /// Creates a manager wired with the production collaborators for the current
  /// platform.
  ///
  /// [processRunner] backs the compiler and driver; [workingDirectory] roots
  /// package-name resolution; [storagePaths] determines where the registry and
  /// compiled binaries live. All are overridable for testing.
  factory DartServiceManager.forCurrentPlatform({
    ServiceLogger logger = const SilentServiceLogger(),
    ProcessRunner processRunner = const SystemProcessRunner(),
    Directory? workingDirectory,
    StoragePaths? storagePaths,
  }) {
    final paths = storagePaths ?? StoragePaths();
    return DartServiceManager(
      resolver: PackageResolver(workingDirectory: workingDirectory),
      manifestLoader: const ManifestLoader(),
      compiler: ServiceCompiler(
        outputDirectory: paths.binDirectory,
        processRunner: processRunner,
        logger: logger,
      ),
      registry: JsonServiceRegistry(paths.registryFile),
      driver: ServiceDriverFactory.forCurrentPlatform(
        processRunner: processRunner,
        logger: logger,
      ),
      logger: logger,
    );
  }

  /// Installs one or all services declared by [packageName].
  ///
  /// When [serviceName] is `null`, every service in the package manifest is
  /// installed. Each service is compiled to a native executable, installed via
  /// the platform driver, and recorded in the registry.
  ///
  /// [path] overrides package-name resolution; [scope] selects user- or
  /// system-level installation. Throws a [ServiceManagerException] subtype on
  /// any failure.
  Future<void> install(
    String packageName, {
    String? serviceName,
    ServiceScope scope = ServiceScope.user,
    String? path,
    bool force = false,
  }) async {
    final packageRoot = await resolver.resolve(packageName, path: path);
    final manifest = await manifestLoader.load(packageRoot);
    final definitions = serviceName == null
        ? manifest.services.values.toList()
        : [manifest.require(serviceName)];

    for (final def in definitions) {
      logger.info('Installing ${manifest.packageName}:${def.name}');
      final binary = await compiler.compileService(
        packageName: manifest.packageName,
        serviceName: def.name,
        packageRoot: packageRoot,
        scriptPath: def.script,
        force: force,
      );
      final descriptor = ServiceDescriptor(
        packageName: manifest.packageName,
        serviceName: def.name,
        executablePath: binary.absolute.path,
        scope: scope,
        description: def.description,
        arguments: def.arguments,
        environment: def.environment,
      );
      await driver.install(descriptor);
      await registry.upsert(
        RegistryEntry(
          packageName: manifest.packageName,
          serviceName: def.name,
          platform: driver.platform,
          scope: scope,
          binaryPath: binary.absolute.path,
          installedAt: DateTime.now().toUtc(),
          status: ServiceStatus.installed,
        ),
      );
    }
  }

  /// Uninstalls one or all services of [packageName] from the OS and registry.
  ///
  /// When [serviceName] is `null`, every recorded service of the package is
  /// removed. The compiled binary cached for each service is deleted too.
  Future<void> uninstall(String packageName, {String? serviceName}) async {
    final entries = await _entriesFor(packageName, serviceName);
    for (final entry in entries) {
      logger.info('Uninstalling ${entry.qualifiedName}');
      await driver.uninstall(_descriptorOf(entry));
      await registry.remove(entry.packageName, entry.serviceName);
      _deleteBinary(entry.binaryPath);
    }
  }

  /// Best-effort removal of a cached service binary; failures are logged, not
  /// fatal, since the OS service is already gone.
  void _deleteBinary(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on IOException catch (e) {
      logger.warning('Could not delete binary $path: $e');
    }
  }

  /// Starts the installed service [serviceName] of [packageName].
  Future<void> start(String packageName, String serviceName) =>
      _lifecycle(packageName, serviceName, driver.start, ServiceStatus.running);

  /// Stops the installed service [serviceName] of [packageName].
  Future<void> stop(String packageName, String serviceName) =>
      _lifecycle(packageName, serviceName, driver.stop, ServiceStatus.stopped);

  /// Pauses the installed service [serviceName] of [packageName].
  ///
  /// Throws [PlatformNotSupportedException] on platforms without pause support.
  Future<void> pause(String packageName, String serviceName) =>
      _lifecycle(packageName, serviceName, driver.pause, ServiceStatus.paused);

  /// Resumes the paused service [serviceName] of [packageName].
  ///
  /// Throws [PlatformNotSupportedException] on platforms without resume support.
  Future<void> resume(String packageName, String serviceName) => _lifecycle(
    packageName,
    serviceName,
    driver.resume,
    ServiceStatus.running,
  );

  /// Restarts the installed service [serviceName] of [packageName].
  Future<void> restart(String packageName, String serviceName) => _lifecycle(
    packageName,
    serviceName,
    driver.restart,
    ServiceStatus.running,
  );

  /// Returns the live [ServiceStatus] of [serviceName] in [packageName].
  ///
  /// Throws [ServiceNotFoundException] when the service is not in the registry.
  Future<ServiceStatus> status(String packageName, String serviceName) async {
    final entry = await _requireEntry(packageName, serviceName);
    return driver.status(_descriptorOf(entry));
  }

  /// Returns every installed service across all packages, each annotated with
  /// its live status.
  Future<List<DartPackageService>> listServices() async {
    final entries = await registry.all();
    return _toPackageServices(entries);
  }

  /// Returns the names of every package that has at least one installed
  /// service.
  Future<List<String>> listPackages() => registry.packages();

  /// Returns the installed services belonging to [packageName], each annotated
  /// with its live status.
  Future<List<DartPackageService>> listPackageServices(
    String packageName,
  ) async {
    final entries = await registry.byPackage(packageName);
    return _toPackageServices(entries);
  }

  Future<void> _lifecycle(
    String packageName,
    String serviceName,
    Future<void> Function(ServiceDescriptor) op,
    ServiceStatus newStatus,
  ) async {
    final entry = await _requireEntry(packageName, serviceName);
    await op(_descriptorOf(entry));
    await registry.upsert(entry.copyWith(status: newStatus));
  }

  Future<List<DartPackageService>> _toPackageServices(
    List<RegistryEntry> entries,
  ) async {
    final services = <DartPackageService>[];
    for (final entry in entries) {
      ServiceStatus status;
      try {
        status = await driver.status(_descriptorOf(entry));
      } on ServiceManagerException catch (e) {
        logger.warning(
          'Could not query status for ${entry.qualifiedName}: ${e.message}',
        );
        status = entry.status;
      }
      services.add(
        DartPackageService(
          packageName: entry.packageName,
          serviceName: entry.serviceName,
          executablePath: entry.binaryPath,
          status: status,
        ),
      );
    }
    return services;
  }

  ServiceDescriptor _descriptorOf(RegistryEntry entry) => ServiceDescriptor(
    packageName: entry.packageName,
    serviceName: entry.serviceName,
    executablePath: entry.binaryPath,
    scope: entry.scope,
  );

  Future<RegistryEntry> _requireEntry(String package, String service) async {
    final entry = await registry.find(package, service);
    if (entry == null) {
      throw ServiceNotFoundException(
        "No installed service '$package:$service'. Install it first.",
      );
    }
    return entry;
  }

  Future<List<RegistryEntry>> _entriesFor(
    String package,
    String? service,
  ) async {
    if (service != null) return [await _requireEntry(package, service)];
    final entries = await registry.byPackage(package);
    if (entries.isEmpty) {
      throw ServiceNotFoundException(
        "No installed services for package '$package'.",
      );
    }
    return entries;
  }
}
