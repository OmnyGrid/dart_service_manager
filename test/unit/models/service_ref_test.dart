import 'package:dart_service_manager/src/util/service_ref.dart';
import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceRef.parse', () {
    test('parses a package-wide reference', () {
      final ref = ServiceRef.parse('analytics');
      expect(ref.package, 'analytics');
      expect(ref.service, isNull);
      expect(ref.isPackageWide, isTrue);
      expect(ref.toString(), 'analytics');
    });

    test('parses a package:service reference', () {
      final ref = ServiceRef.parse('analytics:worker');
      expect(ref.package, 'analytics');
      expect(ref.service, 'worker');
      expect(ref.isPackageWide, isFalse);
      expect(ref.toString(), 'analytics:worker');
    });

    test('trims surrounding whitespace', () {
      expect(ServiceRef.parse('  a : b '), const ServiceRef('a', 'b'));
    });

    test('throws on empty input', () {
      expect(
        () => ServiceRef.parse('   '),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws on too many separators', () {
      expect(
        () => ServiceRef.parse('a:b:c'),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('throws on empty components', () {
      expect(
        () => ServiceRef.parse(':worker'),
        throwsA(isA<ServiceManifestException>()),
      );
      expect(
        () => ServiceRef.parse('pkg:'),
        throwsA(isA<ServiceManifestException>()),
      );
    });

    test('supports equality and hashing', () {
      expect(const ServiceRef('a', 'b'), const ServiceRef('a', 'b'));
      expect(
        const ServiceRef('a', 'b').hashCode,
        const ServiceRef('a', 'b').hashCode,
      );
      expect(const ServiceRef('a'), isNot(const ServiceRef('a', 'b')));
    });
  });
}
