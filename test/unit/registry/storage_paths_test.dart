import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('StoragePaths', () {
    test('uses XDG_DATA_HOME on Linux when set', () {
      final paths = StoragePaths(
        operatingSystem: 'linux',
        environment: {'XDG_DATA_HOME': '/xdg', 'HOME': '/home/me'},
      );
      expect(paths.dataDirectory, p.join('/xdg', 'dart_service_manager'));
      expect(paths.registryFile, endsWith('registry.json'));
      expect(paths.binDirectory, endsWith('bin'));
    });

    test('falls back to ~/.local/share on Linux', () {
      final paths = StoragePaths(
        operatingSystem: 'linux',
        environment: {'HOME': '/home/me'},
      );
      expect(
        paths.dataDirectory,
        p.join('/home/me', '.local', 'share', 'dart_service_manager'),
      );
    });

    test('uses Application Support on macOS', () {
      final paths = StoragePaths(
        operatingSystem: 'macos',
        environment: {'HOME': '/Users/me'},
      );
      expect(
        paths.dataDirectory,
        p.join(
          '/Users/me',
          'Library',
          'Application Support',
          'dart_service_manager',
        ),
      );
    });

    test('uses LOCALAPPDATA on Windows', () {
      final paths = StoragePaths(
        operatingSystem: 'windows',
        environment: {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
      );
      expect(paths.dataDirectory, contains('dart_service_manager'));
    });

    test('throws when Windows LOCALAPPDATA is missing', () {
      final paths = StoragePaths(operatingSystem: 'windows', environment: {});
      expect(
        () => paths.dataDirectory,
        throwsA(isA<ServiceRegistryException>()),
      );
    });

    test('throws on an unsupported platform', () {
      final paths = StoragePaths(operatingSystem: 'solaris', environment: {});
      expect(
        () => paths.dataDirectory,
        throwsA(isA<PlatformNotSupportedException>()),
      );
    });

    test('throws when HOME is missing on Linux', () {
      final paths = StoragePaths(operatingSystem: 'linux', environment: {});
      expect(
        () => paths.dataDirectory,
        throwsA(isA<ServiceRegistryException>()),
      );
    });
  });

  group('RegistryEntry', () {
    test('round-trips through JSON', () {
      final entry = RegistryEntry(
        packageName: 'a',
        serviceName: 's',
        platform: 'macos',
        scope: ServiceScope.system,
        binaryPath: '/bin/s',
        installedAt: DateTime.utc(2026, 6, 9, 12),
        status: ServiceStatus.running,
      );
      final decoded = RegistryEntry.fromJson(entry.toJson());
      expect(decoded.packageName, 'a');
      expect(decoded.scope, ServiceScope.system);
      expect(decoded.status, ServiceStatus.running);
      expect(decoded.installedAt, entry.installedAt);
      expect(decoded.qualifiedName, 'a:s');
    });

    test('defaults scope to user when absent', () {
      final json = {
        'package': 'a',
        'service': 's',
        'platform': 'linux',
        'binary': '/bin/s',
        'installedAt': DateTime.utc(2026).toIso8601String(),
        'status': 'installed',
      };
      expect(RegistryEntry.fromJson(json).scope, ServiceScope.user);
    });
  });
}
