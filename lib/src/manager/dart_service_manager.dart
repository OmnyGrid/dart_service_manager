import 'dart:io';

import 'package:path/path.dart' as p;

import '../compiler/service_compiler.dart';
import '../drivers/platform_service_driver.dart';
import '../drivers/service_driver_factory.dart';
import '../drivers/windows_service_backend.dart';
import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../manifest/manifest_loader.dart';
import '../manifest/package_resolver.dart';
import '../manifest/service_manifest.dart';
import '../models/dart_package_service.dart';
import '../models/service_descriptor.dart';
import '../models/service_info.dart';
import '../models/service_scope.dart';
import '../models/service_status.dart';
import '../process/privilege_checker.dart';
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

  /// Probes whether the process is running elevated, to warn about
  /// scope/privilege mismatches at install time.
  final PrivilegeChecker privilegeChecker;

  /// Creates a manager from explicit collaborators (used in tests).
  DartServiceManager({
    required this.resolver,
    required this.manifestLoader,
    required this.compiler,
    required this.registry,
    required this.driver,
    this.logger = const SilentServiceLogger(),
    this.privilegeChecker = const SystemPrivilegeChecker(),
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
    WindowsServiceBackend windowsBackend =
        WindowsServiceBackend.serviceControlManager,
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
        windowsBackend: windowsBackend,
        storagePaths: paths,
      ),
      logger: logger,
      privilegeChecker: SystemPrivilegeChecker(runner: processRunner),
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
    await _warnScopePrivilege(scope);
    final packageRoot = await resolver.resolve(packageName, path: path);
    final manifest = await manifestLoader.load(packageRoot);
    final definitions = serviceName == null
        ? manifest.services.values.toList()
        : [manifest.require(serviceName)];

    for (final def in definitions) {
      logger.info('Installing ${manifest.packageName}:${def.name}');
      final executablePath = await _resolveExecutable(
        manifest.packageName,
        def,
        packageRoot,
        force,
      );
      final descriptor = _descriptorFromDefinition(
        manifest.packageName,
        def,
        executablePath,
        scope,
        packageRoot,
      );
      await driver.install(descriptor);
      await registry.upsert(
        _entryFromDescriptor(descriptor, status: ServiceStatus.installed),
      );
    }
  }

  /// Installs an already-built executable described by [descriptor] as a
  /// service, bypassing package resolution, manifest loading and compilation.
  ///
  /// Use this to install a binary you already have — e.g. your own CLI via
  /// [ServiceDescriptor.forCurrentExecutable] — with caller-supplied
  /// arguments, environment and runtime policy. The full descriptor is recorded
  /// in the registry so lifecycle, listing and [reconfigure] work without a
  /// manifest.
  ///
  /// Throws [ServiceAlreadyInstalledException] if the service is already
  /// installed and [force] is `false`. When [startNow] is `true`, the service
  /// is started after installation.
  Future<void> installDescriptor(
    ServiceDescriptor descriptor, {
    bool startNow = false,
    bool force = false,
  }) async {
    await _warnScopePrivilege(descriptor.scope);
    final existing = await registry.find(
      descriptor.packageName,
      descriptor.serviceName,
    );
    if (existing != null && !force) {
      throw ServiceAlreadyInstalledException(
        "Service '${descriptor.qualifiedName}' is already installed. Pass "
        'force: true to replace it, or use reconfigure().',
      );
    }
    logger.info('Installing ${descriptor.qualifiedName} (descriptor)');
    await driver.install(descriptor);
    await registry.upsert(
      _entryFromDescriptor(descriptor, status: ServiceStatus.installed),
    );
    if (startNow) await start(descriptor.packageName, descriptor.serviceName);
  }

  /// Re-applies [descriptor] to an already-installed service: re-renders the
  /// native definition, updates the registry, and preserves the running state
  /// (a service that was running is restarted onto the new definition).
  ///
  /// Throws [ServiceNotFoundException] if the service is not installed.
  Future<void> reconfigure(ServiceDescriptor descriptor) async {
    final existing = await _requireEntry(
      descriptor.packageName,
      descriptor.serviceName,
    );
    final wasRunning = await driver.status(descriptor) == ServiceStatus.running;
    logger.info('Reconfiguring ${descriptor.qualifiedName}');
    await driver.install(descriptor);
    await registry.upsert(
      _entryFromDescriptor(
        descriptor,
        status: existing.status,
        installedAt: existing.installedAt,
      ),
    );
    if (wasRunning) await driver.restart(descriptor);
  }

  /// Renders the native service definition (systemd unit, launchd plist or `sc`
  /// command line) for [descriptor] without touching the system — backs the CLI
  /// `--dry-run`.
  String renderDefinition(ServiceDescriptor descriptor) =>
      driver.render(descriptor);

  /// Returns a [ServiceInfo] snapshot for an installed service: its recorded
  /// parameters, its live status, and the native definition the OS runs it from
  /// (the actual command — `ExecStart`, the `sc`/`schtasks` action, …).
  ///
  /// Throws [ServiceNotFoundException] when the service is not in the registry.
  Future<ServiceInfo> describe(String packageName, String serviceName) async {
    final entry = await _requireEntry(packageName, serviceName);
    final descriptor = _descriptorOf(entry);
    return ServiceInfo(
      entry: entry,
      status: await driver.status(descriptor),
      definition: driver.render(descriptor),
    );
  }

  /// Removes any existing installation of [descriptor]'s service and installs it
  /// fresh — a clean teardown-then-recreate (which, for drivers that stage the
  /// runtime, also refreshes the staged binary from [descriptor]'s executable).
  ///
  /// Tolerates the service not being installed yet, so it doubles as a plain
  /// install. When [startNow] is `true` the service is started afterwards.
  Future<void> reinstall(
    ServiceDescriptor descriptor, {
    bool startNow = true,
  }) async {
    final existing = await registry.find(
      descriptor.packageName,
      descriptor.serviceName,
    );
    if (existing != null) {
      logger.info('Removing ${descriptor.qualifiedName} before reinstall');
      try {
        await driver.uninstall(_descriptorOf(existing));
      } on ServiceNotFoundException {
        // The OS no longer knows it; the registry record is enough to proceed.
      }
      await registry.remove(descriptor.packageName, descriptor.serviceName);
    }
    await installDescriptor(descriptor, startNow: startNow, force: true);
  }

  Future<String> _resolveExecutable(
    String packageName,
    ServiceDefinition def,
    String packageRoot,
    bool force,
  ) async {
    if (def.isPrebuilt) {
      final exe = p.isAbsolute(def.executable!)
          ? def.executable!
          : p.normalize(p.join(packageRoot, def.executable!));
      if (!File(exe).existsSync()) {
        throw ServiceInstallationException(
          "Executable '${def.executable}' not found at $exe for "
          '$packageName:${def.name}.',
        );
      }
      return exe;
    }
    final binary = await compiler.compileService(
      packageName: packageName,
      serviceName: def.name,
      packageRoot: packageRoot,
      scriptPath: def.script!,
      force: force,
    );
    return binary.absolute.path;
  }

  /// Warns when the requested [scope] does not match the current privilege
  /// level — the common "ran under sudo but scope is user" (and the reverse)
  /// mistakes — then returns so the install can proceed.
  Future<void> _warnScopePrivilege(ServiceScope scope) async {
    final bool elevated;
    try {
      elevated = await privilegeChecker.isElevated();
    } on Object {
      return; // never let a privilege probe failure block an install
    }
    if (elevated &&
        scope == ServiceScope.user &&
        driver.platform != 'windows') {
      logger.warning(
        'Running as root/sudo but installing a USER-scoped service. User '
        'services (systemctl --user, launchd user agents) usually fail or '
        'install for the wrong user under sudo. Re-run without sudo, or pass '
        '--system (--scope system) to install a system service.',
      );
    } else if (!elevated && scope == ServiceScope.system) {
      logger.warning(
        'Installing a SYSTEM-scoped service without root/administrator '
        'privileges; this will likely fail. Re-run with sudo (Linux/macOS) or '
        'as Administrator (Windows).',
      );
    }
  }

  ServiceDescriptor _descriptorFromDefinition(
    String packageName,
    ServiceDefinition def,
    String executablePath,
    ServiceScope scope,
    String packageRoot,
  ) {
    String? rel(String? value) => value == null
        ? null
        : (p.isAbsolute(value)
              ? value
              : p.normalize(p.join(packageRoot, value)));
    return ServiceDescriptor(
      packageName: packageName,
      serviceName: def.name,
      executablePath: executablePath,
      scope: scope,
      description: def.description,
      arguments: def.arguments,
      environment: def.environment,
      workingDirectory: rel(def.workingDirectory),
      restart: def.restart,
      restartDelay: def.restartDelay,
      autoStart: def.autoStart,
      stopTimeout: def.stopTimeout,
      environmentFile: rel(def.environmentFile),
    );
  }

  RegistryEntry _entryFromDescriptor(
    ServiceDescriptor d, {
    required ServiceStatus status,
    DateTime? installedAt,
  }) => RegistryEntry(
    packageName: d.packageName,
    serviceName: d.serviceName,
    platform: driver.platform,
    scope: d.scope,
    binaryPath: d.executablePath,
    installedAt: installedAt ?? DateTime.now().toUtc(),
    status: status,
    arguments: d.arguments,
    environment: d.environment,
    description: d.description,
    workingDirectory: d.workingDirectory,
    restart: d.restart,
    restartDelay: d.restartDelay,
    autoStart: d.autoStart,
    stopTimeout: d.stopTimeout,
    environmentFile: d.environmentFile,
  );

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
  ///
  /// Only binaries the manager itself compiled into its managed output
  /// directory are removed. Externally-provided executables — an
  /// `installDescriptor` target, a manifest `executable:` path, or the Dart VM
  /// itself for a `forCurrentExecutable` install — are left untouched, so
  /// uninstall can never delete a binary it did not create.
  void _deleteBinary(String path) {
    if (!_isManagedBinary(path)) {
      logger.debug('Keeping externally-provided binary $path');
      return;
    }
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on IOException catch (e) {
      logger.warning('Could not delete binary $path: $e');
    }
  }

  /// Whether [path] lives inside the compiler's managed output directory (i.e.
  /// the manager produced it), making it safe to delete on uninstall.
  bool _isManagedBinary(String path) =>
      p.isWithin(p.absolute(compiler.outputDirectory), p.absolute(path));

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
    description: entry.description,
    arguments: entry.arguments,
    environment: entry.environment,
    workingDirectory: entry.workingDirectory,
    restart: entry.restart,
    restartDelay: entry.restartDelay,
    autoStart: entry.autoStart,
    stopTimeout: entry.stopTimeout,
    environmentFile: entry.environmentFile,
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
