import 'registry_entry.dart';

/// Repository contract for the manager's persistent record of installed
/// services.
///
/// Encapsulating storage behind this interface keeps the rest of the package
/// agnostic to *how* the registry is persisted (a JSON file in production, an
/// in-memory map in tests) and gives a single seam for transactions and error
/// handling.
abstract interface class ServiceRegistry {
  /// Returns every recorded entry.
  Future<List<RegistryEntry>> all();

  /// Returns the entry for [package]/[service], or `null` when absent.
  Future<RegistryEntry?> find(String package, String service);

  /// Returns every entry belonging to [package].
  Future<List<RegistryEntry>> byPackage(String package);

  /// Returns the distinct package names that have at least one entry.
  Future<List<String>> packages();

  /// Inserts [entry], replacing any existing entry with the same
  /// package/service pair.
  Future<void> upsert(RegistryEntry entry);

  /// Removes the entry for [package]/[service] if present.
  Future<void> remove(String package, String service);
}
