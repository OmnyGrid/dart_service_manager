import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/service_exception.dart';
import '../util/json.dart';
import 'registry_entry.dart';
import 'service_registry.dart';

/// A [ServiceRegistry] backed by a single JSON file on disk.
///
/// The file holds a `{ "version": 1, "services": [...] }` document. Writes are
/// atomic — content is written to a sibling temp file and renamed over the
/// target — so a crash mid-write can never corrupt the registry. All reads and
/// writes are serialised through an internal future chain to avoid interleaving
/// concurrent mutations within a single process.
final class JsonServiceRegistry implements ServiceRegistry {
  /// The schema version written into the registry file.
  static const int schemaVersion = 1;

  /// The absolute path to the registry JSON file.
  final String filePath;

  Future<void> _lock = Future.value();

  /// Creates a registry persisted at [filePath].
  JsonServiceRegistry(this.filePath);

  @override
  Future<List<RegistryEntry>> all() => _synchronized(_readAll);

  @override
  Future<RegistryEntry?> find(String package, String service) =>
      _synchronized(() async {
        final entries = await _readAll();
        for (final e in entries) {
          if (e.packageName == package && e.serviceName == service) return e;
        }
        return null;
      });

  @override
  Future<List<RegistryEntry>> byPackage(String package) =>
      _synchronized(() async {
        final entries = await _readAll();
        return entries.where((e) => e.packageName == package).toList();
      });

  @override
  Future<List<String>> packages() => _synchronized(() async {
    final entries = await _readAll();
    final names = <String>{for (final e in entries) e.packageName};
    final sorted = names.toList()..sort();
    return sorted;
  });

  @override
  Future<void> upsert(RegistryEntry entry) => _synchronized(() async {
    final entries = await _readAll();
    entries.removeWhere(
      (e) =>
          e.packageName == entry.packageName &&
          e.serviceName == entry.serviceName,
    );
    entries.add(entry);
    await _writeAll(entries);
  });

  @override
  Future<void> remove(String package, String service) =>
      _synchronized(() async {
        final entries = await _readAll();
        final before = entries.length;
        entries.removeWhere(
          (e) => e.packageName == package && e.serviceName == service,
        );
        if (entries.length != before) await _writeAll(entries);
      });

  /// Serialises [action] after any in-flight registry operation completes.
  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    // Keep the chain alive but swallow this op's error so the next caller is
    // not poisoned by a prior failure.
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<RegistryEntry>> _readAll() async {
    final file = File(filePath);
    if (!file.existsSync()) return [];
    final String content;
    try {
      content = await file.readAsString();
    } on IOException catch (e) {
      throw ServiceRegistryException(
        'Failed to read registry $filePath',
        cause: e,
      );
    }
    if (content.trim().isEmpty) return [];
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (e) {
      throw ServiceRegistryException(
        'Registry file $filePath is not valid JSON',
        cause: e,
      );
    }
    final root = Json.asObject(decoded, 'registry');
    return Json.objectList(
      root,
      'services',
    ).map(RegistryEntry.fromJson).toList();
  }

  Future<void> _writeAll(List<RegistryEntry> entries) async {
    final dir = Directory(p.dirname(filePath));
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final payload = const JsonEncoder.withIndent('  ').convert({
        'version': schemaVersion,
        'services': [for (final e in entries) e.toJson()],
      });
      final tmp = File('$filePath.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(filePath);
    } on IOException catch (e) {
      throw ServiceRegistryException(
        'Failed to write registry $filePath',
        cause: e,
      );
    }
  }
}
