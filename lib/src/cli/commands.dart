import 'package:args/command_runner.dart';

import '../manager/dart_service_manager.dart';
import '../models/dart_package_service.dart';
import '../models/service_scope.dart';
import '../util/service_ref.dart';
import 'cli_runner.dart';

/// Shared behaviour for every `dart-service` subcommand: access to the
/// per-invocation [DartServiceManager], the output sink, and the parsed global
/// options.
abstract class ServiceCommand extends Command<int> {
  /// Builds the manager for this invocation.
  final ManagerFactory managerFactory;

  /// The sink all human-readable output is written to.
  final StringSink out;

  /// Creates a service command.
  ServiceCommand(this.managerFactory, this.out);

  /// Whether `--verbose` was passed.
  bool get verbose => globalResults?['verbose'] as bool? ?? false;

  /// The `--scope` global option.
  ServiceScope get scope => scopeFromGlobals(globalResults);

  /// The `--path` global option, if any.
  String? get path => globalResults?['path'] as String?;

  /// The manager for this invocation.
  DartServiceManager get manager => managerFactory(verbose: verbose);

  /// Returns the single positional argument, or throws a [UsageException].
  String requireRef() {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageException(
        'Expected exactly one "package" or "package:service" argument.',
        usage,
      );
    }
    return rest.single;
  }

  /// Resolves the service names targeted by [ref]: the single named service, or
  /// every installed service of the package when package-wide.
  Future<List<String>> targetedServices(ServiceRef ref) async {
    if (ref.service != null) return [ref.service!];
    final services = await manager.listPackageServices(ref.package);
    return services.map((s) => s.serviceName).toList();
  }
}

/// `install <package[:service]>` — compile and install services.
class InstallCommand extends ServiceCommand {
  InstallCommand(super.factory, super.out);

  @override
  String get name => 'install';
  @override
  String get description =>
      'Compile and install one or all services of a package.';
  @override
  String get invocation => 'dart-service install <package[:service]>';

  @override
  Future<int> run() async {
    final ref = ServiceRef.parse(requireRef());
    await manager.install(
      ref.package,
      serviceName: ref.service,
      scope: scope,
      path: path,
    );
    out.writeln('Installed $ref (scope: ${scope.name}).');
    return 0;
  }
}

/// `uninstall <package[:service]>` — remove services.
class UninstallCommand extends ServiceCommand {
  UninstallCommand(super.factory, super.out);

  @override
  String get name => 'uninstall';
  @override
  String get description => 'Uninstall one or all services of a package.';
  @override
  String get invocation => 'dart-service uninstall <package[:service]>';

  @override
  Future<int> run() async {
    final ref = ServiceRef.parse(requireRef());
    await manager.uninstall(ref.package, serviceName: ref.service);
    out.writeln('Uninstalled $ref.');
    return 0;
  }
}

/// `start <package[:service]>`.
class StartCommand extends ServiceCommand {
  StartCommand(super.factory, super.out);

  @override
  String get name => 'start';
  @override
  String get description => 'Start one or all services of a package.';
  @override
  String get invocation => 'dart-service start <package[:service]>';

  @override
  Future<int> run() async {
    final ref = ServiceRef.parse(requireRef());
    for (final service in await targetedServices(ref)) {
      await manager.start(ref.package, service);
      out.writeln('Started ${ref.package}:$service.');
    }
    return 0;
  }
}

/// `stop <package[:service]>`.
class StopCommand extends ServiceCommand {
  StopCommand(super.factory, super.out);

  @override
  String get name => 'stop';
  @override
  String get description => 'Stop one or all services of a package.';
  @override
  String get invocation => 'dart-service stop <package[:service]>';

  @override
  Future<int> run() async {
    final ref = ServiceRef.parse(requireRef());
    for (final service in await targetedServices(ref)) {
      await manager.stop(ref.package, service);
      out.writeln('Stopped ${ref.package}:$service.');
    }
    return 0;
  }
}

/// `pause <package[:service]>`.
class PauseCommand extends ServiceCommand {
  PauseCommand(super.factory, super.out);

  @override
  String get name => 'pause';
  @override
  String get description =>
      'Pause one or all services of a package (where supported).';
  @override
  String get invocation => 'dart-service pause <package[:service]>';

  @override
  Future<int> run() async {
    final ref = ServiceRef.parse(requireRef());
    for (final service in await targetedServices(ref)) {
      await manager.pause(ref.package, service);
      out.writeln('Paused ${ref.package}:$service.');
    }
    return 0;
  }
}

/// `resume <package[:service]>`.
class ResumeCommand extends ServiceCommand {
  ResumeCommand(super.factory, super.out);

  @override
  String get name => 'resume';
  @override
  String get description =>
      'Resume one or all paused services of a package (where supported).';
  @override
  String get invocation => 'dart-service resume <package[:service]>';

  @override
  Future<int> run() async {
    final ref = ServiceRef.parse(requireRef());
    for (final service in await targetedServices(ref)) {
      await manager.resume(ref.package, service);
      out.writeln('Resumed ${ref.package}:$service.');
    }
    return 0;
  }
}

/// `restart <package[:service]>`.
class RestartCommand extends ServiceCommand {
  RestartCommand(super.factory, super.out);

  @override
  String get name => 'restart';
  @override
  String get description => 'Restart one or all services of a package.';
  @override
  String get invocation => 'dart-service restart <package[:service]>';

  @override
  Future<int> run() async {
    final ref = ServiceRef.parse(requireRef());
    for (final service in await targetedServices(ref)) {
      await manager.restart(ref.package, service);
      out.writeln('Restarted ${ref.package}:$service.');
    }
    return 0;
  }
}

/// `status <package[:service]>`.
class StatusCommand extends ServiceCommand {
  StatusCommand(super.factory, super.out);

  @override
  String get name => 'status';
  @override
  String get description => 'Show the status of one or all services.';
  @override
  String get invocation => 'dart-service status <package[:service]>';

  @override
  Future<int> run() async {
    final ref = ServiceRef.parse(requireRef());
    if (ref.service != null) {
      final status = await manager.status(ref.package, ref.service!);
      out.writeln('${ref.package}:${ref.service}  ${status.name}');
      return 0;
    }
    final services = await manager.listPackageServices(ref.package);
    _printServices(out, services);
    return 0;
  }
}

/// `list` — list every installed service.
class ListCommand extends ServiceCommand {
  ListCommand(super.factory, super.out);

  @override
  String get name => 'list';
  @override
  String get description => 'List all installed services.';
  @override
  String get invocation => 'dart-service list';

  @override
  Future<int> run() async {
    _printServices(out, await manager.listServices());
    return 0;
  }
}

/// `packages` — list packages that have installed services.
class PackagesCommand extends ServiceCommand {
  PackagesCommand(super.factory, super.out);

  @override
  String get name => 'packages';
  @override
  String get description => 'List packages that have installed services.';
  @override
  String get invocation => 'dart-service packages';

  @override
  Future<int> run() async {
    final packages = await manager.listPackages();
    if (packages.isEmpty) {
      out.writeln('No packages have installed services.');
    } else {
      for (final pkg in packages) {
        out.writeln(pkg);
      }
    }
    return 0;
  }
}

/// `services <package>` — list services for a package.
class ServicesCommand extends ServiceCommand {
  ServicesCommand(super.factory, super.out);

  @override
  String get name => 'services';
  @override
  String get description => 'List the installed services of a package.';
  @override
  String get invocation => 'dart-service services <package>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageException('Expected exactly one "package" argument.', usage);
    }
    _printServices(out, await manager.listPackageServices(rest.single));
    return 0;
  }
}

void _printServices(StringSink out, List<DartPackageService> services) {
  if (services.isEmpty) {
    out.writeln('No services installed.');
    return;
  }
  final width = services
      .map((s) => s.qualifiedName.length)
      .reduce((a, b) => a > b ? a : b);
  for (final s in services) {
    out.writeln('${s.qualifiedName.padRight(width)}  ${s.status.name}');
  }
}
