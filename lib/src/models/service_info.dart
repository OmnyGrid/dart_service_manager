import 'package:meta/meta.dart';

import '../registry/registry_entry.dart';
import 'service_status.dart';

/// A read-only snapshot of an installed service: its recorded parameters, its
/// current live status, and the native definition the OS runs it from.
///
/// Returned by `DartServiceManager.describe`. [entry] holds the persisted
/// configuration (binary, arguments, environment, scope, policy, install time);
/// [status] is re-queried live from the platform driver; [definition] is the
/// rendered native artifact — a systemd unit, a launchd plist, the `sc` command
/// line, or the Task Scheduler XML — i.e. the **actual command** the OS uses to
/// run the service.
@immutable
class ServiceInfo {
  /// The persisted registry record for the service.
  final RegistryEntry entry;

  /// The live status, re-queried from the platform driver.
  final ServiceStatus status;

  /// The rendered native service definition (the same string `render`/`--dry-run`
  /// produces), reflecting the executable path and arguments the OS launches.
  final String definition;

  /// Creates a service-info snapshot.
  const ServiceInfo({
    required this.entry,
    required this.status,
    required this.definition,
  });

  @override
  String toString() => 'ServiceInfo(${entry.qualifiedName}, ${status.name})';
}
