import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:dart_service_manager/src/util/json.dart';
import 'package:test/test.dart';

void main() {
  group('Json.asObject', () {
    test('casts a map', () {
      expect(Json.asObject({'a': 1}), {'a': 1});
    });
    test('throws on a non-map', () {
      expect(() => Json.asObject(42), throwsA(isA<ServiceRegistryException>()));
    });
  });

  group('Json.requireString', () {
    test('returns a present string', () {
      expect(Json.requireString({'k': 'v'}, 'k'), 'v');
    });
    test('throws when missing or wrong type', () {
      expect(
        () => Json.requireString({}, 'k'),
        throwsA(isA<ServiceRegistryException>()),
      );
      expect(
        () => Json.requireString({'k': 1}, 'k'),
        throwsA(isA<ServiceRegistryException>()),
      );
    });
  });

  group('Json.optString', () {
    test('returns null when absent and the value when present', () {
      expect(Json.optString({}, 'k'), isNull);
      expect(Json.optString({'k': 'v'}, 'k'), 'v');
    });
    test('throws when present but not a string', () {
      expect(
        () => Json.optString({'k': 1}, 'k'),
        throwsA(isA<ServiceRegistryException>()),
      );
    });
  });

  group('Json.requireTimestamp', () {
    test('parses ISO-8601 to UTC', () {
      final ts = Json.requireTimestamp({'t': '2026-06-09T10:00:00Z'}, 't');
      expect(ts.isUtc, isTrue);
      expect(ts.year, 2026);
    });
    test('throws on an invalid timestamp', () {
      expect(
        () => Json.requireTimestamp({'t': 'not-a-date'}, 't'),
        throwsA(isA<ServiceRegistryException>()),
      );
    });
  });

  group('Json.objectList', () {
    test('returns empty when absent', () {
      expect(Json.objectList({}, 'k'), isEmpty);
    });
    test('maps a list of objects', () {
      expect(
        Json.objectList({
          'k': [
            {'a': 1},
          ],
        }, 'k'),
        [
          {'a': 1},
        ],
      );
    });
    test('throws when not a list', () {
      expect(
        () => Json.objectList({'k': 'x'}, 'k'),
        throwsA(isA<ServiceRegistryException>()),
      );
    });
    test('throws when an element is not an object', () {
      expect(
        () => Json.objectList({
          'k': [1],
        }, 'k'),
        throwsA(isA<ServiceRegistryException>()),
      );
    });
  });
}
