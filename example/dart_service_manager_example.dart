import 'package:dart_service_manager/dart_service_manager.dart';

/// Demonstrates the programmatic API: install every service declared by a
/// package, start one, query its status, list what is installed, then tidy up.
///
/// Run from a directory containing (or able to resolve) the target package:
///
/// ```bash
/// dart run example/dart_service_manager_example.dart
/// ```
///
/// See `example/sample_package` for a package that declares services.
Future<void> main() async {
  final manager = DartServiceManager.forCurrentPlatform(
    logger: ConsoleServiceLogger(),
  );

  const package = 'sample_package';

  // Compile and install every service the package declares.
  await manager.install(package, path: 'example/sample_package');

  // Start a specific service and inspect it.
  await manager.start(package, 'worker');
  final status = await manager.status(package, 'worker');
  print('$package:worker is ${status.name}');

  // Enumerate what is installed.
  for (final service in await manager.listServices()) {
    print('${service.qualifiedName.padRight(28)} ${service.status.name}');
  }
  print('Packages with services: ${await manager.listPackages()}');

  // Clean up.
  await manager.stop(package, 'worker');
  await manager.uninstall(package);
}
