import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../errors/service_exception.dart';
import 'service_manifest.dart';

/// Loads and validates a package's [ServiceManifest] from its `pubspec.yaml`.
///
/// The manifest is the `dart_services:` section of the package's pubspec; the
/// package name is taken from the pubspec's own `name:` field. Parsing is split
/// out into [parsePubspec] so it can be unit-tested without touching disk.
final class ManifestLoader {
  /// Creates a manifest loader.
  const ManifestLoader();

  /// Reads `pubspec.yaml` from [packageRoot] and returns its [ServiceManifest].
  ///
  /// Throws [ServiceManifestException] if the pubspec is missing, unparseable,
  /// or declares no services.
  Future<ServiceManifest> load(String packageRoot) async {
    final pubspec = File(p.join(packageRoot, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw ServiceManifestException(
        'No pubspec.yaml found at ${pubspec.path}.',
      );
    }
    final String content;
    try {
      content = await pubspec.readAsString();
    } on IOException catch (e) {
      throw ServiceManifestException(
        'Failed to read ${pubspec.path}',
        cause: e,
      );
    }
    return parsePubspec(content);
  }

  /// Parses pubspec [content] into a [ServiceManifest].
  ///
  /// Exposed for testing and for callers that already hold the pubspec text.
  ServiceManifest parsePubspec(String content) {
    final YamlNode root;
    try {
      root = loadYamlNode(content);
    } on YamlException catch (e) {
      throw ServiceManifestException('Invalid pubspec.yaml', cause: e);
    }
    if (root is! YamlMap) {
      throw const ServiceManifestException(
        'pubspec.yaml must be a YAML mapping.',
      );
    }
    final name = root['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const ServiceManifestException(
        "pubspec.yaml is missing a 'name' field.",
      );
    }
    final section = root['dart_services'];
    if (section != null && section is! YamlMap) {
      throw ServiceManifestException(
        "The 'dart_services' section of package '$name' must be a mapping.",
      );
    }
    return ServiceManifest.parse(name.trim(), section as YamlMap?);
  }
}
