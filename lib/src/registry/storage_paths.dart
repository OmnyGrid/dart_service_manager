import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/service_exception.dart';

/// Resolves the per-user data directories the manager uses to persist its
/// registry and store compiled service binaries.
///
/// Locations follow each platform's convention:
/// * Linux — `$XDG_DATA_HOME` or `~/.local/share/dart_service_manager`
/// * macOS — `~/Library/Application Support/dart_service_manager`
/// * Windows — `%LOCALAPPDATA%\dart_service_manager`
///
/// The environment is injectable so resolution is deterministic in tests.
final class StoragePaths {
  /// The application directory name used under each platform's data root.
  static const String appDirName = 'dart_service_manager';

  /// The operating system identifier (`Platform.operatingSystem`-compatible).
  final String operatingSystem;

  /// The environment used to look up home/data directories.
  final Map<String, String> environment;

  /// Creates a storage-path resolver.
  StoragePaths({String? operatingSystem, Map<String, String>? environment})
    : operatingSystem = operatingSystem ?? Platform.operatingSystem,
      environment = environment ?? Platform.environment;

  /// The root data directory for the manager, created on demand by callers.
  String get dataDirectory {
    switch (operatingSystem) {
      case 'linux':
        final xdg = environment['XDG_DATA_HOME'];
        final base = (xdg != null && xdg.isNotEmpty)
            ? xdg
            : p.join(_home, '.local', 'share');
        return p.join(base, appDirName);
      case 'macos':
        return p.join(_home, 'Library', 'Application Support', appDirName);
      case 'windows':
        final local = environment['LOCALAPPDATA'];
        if (local == null || local.isEmpty) {
          throw const ServiceRegistryException(
            'LOCALAPPDATA is not set; cannot resolve the data directory.',
          );
        }
        return p.join(local, appDirName);
      default:
        throw PlatformNotSupportedException(
          'Unsupported platform: $operatingSystem',
        );
    }
  }

  /// The path to the registry JSON file.
  String get registryFile => p.join(dataDirectory, 'registry.json');

  /// The directory under which compiled service binaries are stored.
  String get binDirectory => p.join(dataDirectory, 'bin');

  String get _home {
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw const ServiceRegistryException(
        'Neither HOME nor USERPROFILE is set; cannot resolve the home '
        'directory.',
      );
    }
    return home;
  }
}
