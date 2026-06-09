import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceManifest.parse', () {
    test('parses the shorthand script form', () {
      final manifest = ServiceManifest.parse('analytics', {
        'worker': 'bin/worker.dart',
      });
      expect(manifest.packageName, 'analytics');
      expect(manifest.serviceNames, ['worker']);
      expect(manifest.require('worker').script, 'bin/worker.dart');
    });

    test('parses the map form with description, args and env', () {
      final manifest = ServiceManifest.parse('analytics', {
        'worker': {
          'script': 'bin/worker.dart',
          'description': 'The worker',
          'args': ['--flag', 1],
          'env': {'LOG': 'debug'},
        },
      });
      final def = manifest.require('worker');
      expect(def.description, 'The worker');
      expect(def.arguments, ['--flag', '1']);
      expect(def.environment, {'LOG': 'debug'});
    });

    test('trims whitespace around script paths', () {
      final manifest = ServiceManifest.parse('p', {'s': '  bin/s.dart  '});
      expect(manifest.require('s').script, 'bin/s.dart');
    });

    test('throws when no services are declared', () {
      expect(
        () => ServiceManifest.parse('p', null),
        throwsA(isA<ServiceManifestException>()),
      );
      expect(
        () => ServiceManifest.parse('p', {}),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws on an invalid service name', () {
      expect(
        () => ServiceManifest.parse('p', {'bad name': 'bin/x.dart'}),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws when the map form omits a script', () {
      expect(
        () => ServiceManifest.parse('p', {
          's': {'description': 'x'},
        }),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws when an entry is neither a string nor a map', () {
      expect(
        () => ServiceManifest.parse('p', {'s': 42}),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws on a malformed args field', () {
      expect(
        () => ServiceManifest.parse('p', {
          's': {'script': 'bin/s.dart', 'args': 'not-a-list'},
        }),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws on a malformed env field', () {
      expect(
        () => ServiceManifest.parse('p', {
          's': {'script': 'bin/s.dart', 'env': 'not-a-map'},
        }),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws when the map-form script is blank', () {
      expect(
        () => ServiceManifest.parse('p', {
          's': {'script': '   '},
        }),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws when the shorthand script is blank', () {
      expect(
        () => ServiceManifest.parse('p', {'s': '   '}),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('definitions support value equality', () {
      final a = ServiceManifest.parse('p', {'s': 'bin/s.dart'}).require('s');
      final b = ServiceManifest.parse('p', {'s': 'bin/s.dart'}).require('s');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('bin/s.dart'));
    });

    test('require reports the available services', () {
      final manifest = ServiceManifest.parse('p', {'a': 'bin/a.dart'});
      expect(manifest.hasService('a'), isTrue);
      expect(manifest.hasService('b'), isFalse);
      expect(
        () => manifest.require('b'),
        throwsA(
          isA<ServiceManifestException>().having(
            (e) => e.message,
            'message',
            contains('a'),
          ),
        ),
      );
    });
  });
}
