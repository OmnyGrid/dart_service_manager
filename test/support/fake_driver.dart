import 'package:dart_service_manager/dart_service_manager.dart';

/// A [PlatformServiceDriver] that records operations in memory, for exercising
/// [DartServiceManager] without touching a real init system.
class FakeServiceDriver implements PlatformServiceDriver {
  @override
  final String platform;

  @override
  final bool supportsPauseResume;

  /// The operations performed, as `verb:systemName` strings, in order.
  final List<String> operations = [];

  /// The status returned by [status], keyed by qualified service name.
  final Map<String, ServiceStatus> statuses = {};

  /// The default status when none is configured for a service.
  ServiceStatus defaultStatus;

  /// When `true`, [status] throws a [ServiceRegistryException] to exercise the
  /// manager's status-query fallback path.
  bool throwOnStatus;

  FakeServiceDriver({
    this.platform = 'linux',
    this.supportsPauseResume = false,
    this.defaultStatus = ServiceStatus.running,
    this.throwOnStatus = false,
  });

  void _record(String verb, ServiceDescriptor s) =>
      operations.add('$verb:${s.qualifiedName}');

  @override
  Future<void> install(ServiceDescriptor service) async =>
      _record('install', service);

  @override
  Future<void> uninstall(ServiceDescriptor service) async =>
      _record('uninstall', service);

  @override
  Future<void> start(ServiceDescriptor service) async =>
      _record('start', service);

  @override
  Future<void> stop(ServiceDescriptor service) async =>
      _record('stop', service);

  @override
  Future<void> restart(ServiceDescriptor service) async =>
      _record('restart', service);

  @override
  Future<void> pause(ServiceDescriptor service) async {
    if (!supportsPauseResume) {
      throw const PlatformNotSupportedException('pause unsupported');
    }
    _record('pause', service);
  }

  @override
  Future<void> resume(ServiceDescriptor service) async {
    if (!supportsPauseResume) {
      throw const PlatformNotSupportedException('resume unsupported');
    }
    _record('resume', service);
  }

  @override
  Future<ServiceStatus> status(ServiceDescriptor service) async {
    if (throwOnStatus) {
      throw const ServiceRegistryException('status query failed');
    }
    return statuses[service.qualifiedName] ?? defaultStatus;
  }
}
