import '../errors/service_exception.dart';

/// Centralised, defensive helpers for reading values out of decoded JSON
/// (`Map<String, dynamic>`) without scattering type checks across the codebase.
///
/// Every accessor throws a [ServiceRegistryException] with a precise message
/// when a field is missing or has the wrong type, so malformed registry files
/// surface a single, actionable error instead of an opaque [TypeError].
final class Json {
  const Json._();

  /// Casts [value] to a `Map<String, dynamic>` or throws.
  ///
  /// [what] names the value being decoded for use in the error message.
  static Map<String, dynamic> asObject(Object? value, [String what = 'value']) {
    if (value is Map) return value.cast<String, dynamic>();
    throw ServiceRegistryException('Expected $what to be a JSON object');
  }

  /// Returns the required string field [key], or throws if missing/invalid.
  static String requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) return value;
    throw ServiceRegistryException("Missing or invalid string field '$key'");
  }

  /// Returns the optional string field [key], or `null` when absent.
  ///
  /// Throws when present but not a string.
  static String? optString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw ServiceRegistryException("Invalid string field '$key'");
  }

  /// Returns the required UTC [DateTime] parsed from ISO-8601 field [key].
  static DateTime requireTimestamp(Map<String, dynamic> json, String key) {
    final raw = requireString(json, key);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw ServiceRegistryException("Invalid timestamp field '$key': '$raw'");
    }
    return parsed.toUtc();
  }

  /// Returns the optional list field [key] as `List<Map<String, dynamic>>`.
  ///
  /// Returns an empty list when absent. Throws when present but not a list of
  /// objects.
  static List<Map<String, dynamic>> objectList(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List) {
      throw ServiceRegistryException("Invalid list field '$key'");
    }
    return value.map((e) => asObject(e, "$key entry")).toList(growable: false);
  }
}
