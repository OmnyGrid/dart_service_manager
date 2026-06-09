import 'package:dart_service_manager/dart_service_manager.dart';

/// An in-memory [ServiceRegistry] for fast, isolated tests.
class InMemoryServiceRegistry implements ServiceRegistry {
  final List<RegistryEntry> _entries = [];

  /// Seeds the registry with [initial] entries.
  InMemoryServiceRegistry([List<RegistryEntry> initial = const []]) {
    _entries.addAll(initial);
  }

  @override
  Future<List<RegistryEntry>> all() async => List.of(_entries);

  @override
  Future<List<RegistryEntry>> byPackage(String package) async =>
      _entries.where((e) => e.packageName == package).toList();

  @override
  Future<RegistryEntry?> find(String package, String service) async {
    for (final e in _entries) {
      if (e.packageName == package && e.serviceName == service) return e;
    }
    return null;
  }

  @override
  Future<List<String>> packages() async {
    final names = <String>{for (final e in _entries) e.packageName};
    return names.toList()..sort();
  }

  @override
  Future<void> remove(String package, String service) async {
    _entries.removeWhere(
      (e) => e.packageName == package && e.serviceName == service,
    );
  }

  @override
  Future<void> upsert(RegistryEntry entry) async {
    _entries.removeWhere(
      (e) =>
          e.packageName == entry.packageName &&
          e.serviceName == entry.serviceName,
    );
    _entries.add(entry);
  }
}
