import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const loader = ManifestLoader();

  group('ManifestLoader.parsePubspec', () {
    test('reads the package name and dart_services section', () {
      final manifest = loader.parsePubspec('''
name: analytics_server
dart_services:
  worker:
    script: bin/worker.dart
  scheduler: bin/scheduler.dart
''');
      expect(manifest.packageName, 'analytics_server');
      expect(manifest.serviceNames, containsAll(['worker', 'scheduler']));
      expect(manifest.require('scheduler').script, 'bin/scheduler.dart');
    });

    test('throws when name is missing', () {
      expect(
        () => loader.parsePubspec('dart_services:\n  w: bin/w.dart\n'),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws when dart_services is not a mapping', () {
      expect(
        () => loader.parsePubspec('name: p\ndart_services: oops\n'),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws on invalid YAML', () {
      expect(
        () => loader.parsePubspec('name: : :\n  - bad'),
        throwsA(isA<ServiceManifestException>()),
      );
    });
  });

  group('ManifestLoader.load', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('dsm_manifest'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('loads from a pubspec.yaml on disk', () async {
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: demo
dart_services:
  worker: bin/worker.dart
''');
      final manifest = await loader.load(dir.path);
      expect(manifest.packageName, 'demo');
      expect(manifest.require('worker').script, 'bin/worker.dart');
    });

    test('throws when pubspec.yaml is missing', () {
      expect(
        () => loader.load(dir.path),
        throwsA(isA<ServiceManifestException>()),
      );
    });
  });
}
