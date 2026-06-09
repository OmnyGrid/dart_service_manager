import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../errors/service_exception.dart';

/// Resolves a Dart package *name* to the directory that contains its
/// `pubspec.yaml`.
///
/// Resolution order (first match wins):
/// 1. An explicit `path` override, if supplied.
/// 2. The current working directory, when its pubspec `name` matches.
/// 3. The `.dart_tool/package_config.json` of the current directory, which maps
///    every dependency (path or pub-cache) to its root URI.
///
/// All filesystem roots are configurable so the resolver is fully testable.
final class PackageResolver {
  /// The directory treated as "current" for CWD and package-config lookups.
  final Directory workingDirectory;

  /// Creates a resolver rooted at [workingDirectory] (defaults to the process
  /// current directory).
  PackageResolver({Directory? workingDirectory})
    : workingDirectory = workingDirectory ?? Directory.current;

  /// Resolves [packageName] to an absolute package-root directory path.
  ///
  /// When [path] is given it is used directly (after verifying it holds a
  /// `pubspec.yaml`) and [packageName] is only used for error messages.
  ///
  /// Throws [ServiceNotFoundException] when the package cannot be located.
  Future<String> resolve(String packageName, {String? path}) async {
    if (path != null) {
      final root = p.absolute(path);
      if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
        throw ServiceNotFoundException(
          "No pubspec.yaml found at '$root' for package '$packageName'.",
        );
      }
      return root;
    }

    final cwd = workingDirectory.path;
    if (_pubspecName(cwd) == packageName) {
      return p.absolute(cwd);
    }

    final fromConfig = _fromPackageConfig(packageName);
    if (fromConfig != null) return fromConfig;

    throw ServiceNotFoundException(
      "Could not resolve package '$packageName'. Run from the package "
      'directory, ensure it is a resolved dependency '
      '(.dart_tool/package_config.json), or pass an explicit path.',
    );
  }

  String? _pubspecName(String dir) {
    final pubspec = File(p.join(dir, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    try {
      final node = loadYamlNode(pubspec.readAsStringSync());
      if (node is YamlMap && node['name'] is String) {
        return (node['name'] as String).trim();
      }
    } on YamlException {
      return null;
    }
    return null;
  }

  String? _fromPackageConfig(String packageName) {
    final configFile = File(
      p.join(workingDirectory.path, '.dart_tool', 'package_config.json'),
    );
    if (!configFile.existsSync()) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(configFile.readAsStringSync());
    } on FormatException catch (e) {
      throw ServiceManifestException('Invalid ${configFile.path}', cause: e);
    }
    if (decoded is! Map) return null;
    final packages = decoded['packages'];
    if (packages is! List) return null;
    for (final entry in packages) {
      if (entry is Map && entry['name'] == packageName) {
        final rootUri = entry['rootUri'];
        if (rootUri is! String) return null;
        return _resolveRootUri(rootUri, configFile.parent.path);
      }
    }
    return null;
  }

  /// Resolves a `rootUri` from package_config.json, which may be a `file://`
  /// URI or a path relative to the `.dart_tool` directory.
  String _resolveRootUri(String rootUri, String dartToolDir) {
    if (rootUri.startsWith('file://')) {
      return p.normalize(Uri.parse(rootUri).toFilePath());
    }
    return p.normalize(p.join(dartToolDir, rootUri));
  }
}
