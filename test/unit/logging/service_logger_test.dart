import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

void main() {
  group('LogLevel', () {
    test('severity follows declaration order', () {
      expect(LogLevel.debug.severity, lessThan(LogLevel.error.severity));
    });
  });

  group('SilentServiceLogger', () {
    test('is disabled at every level and logs nothing', () {
      const logger = SilentServiceLogger();
      for (final level in LogLevel.values) {
        expect(logger.isEnabled(level), isFalse);
      }
      logger.info('ignored'); // must not throw
    });
  });

  group('ConsoleServiceLogger', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    test('honours the minimum level', () {
      final logger = ConsoleServiceLogger(minLevel: LogLevel.warning);
      expect(logger.isEnabled(LogLevel.info), isFalse);
      expect(logger.isEnabled(LogLevel.error), isTrue);
    });

    test('drops messages below the minimum level', () {
      ConsoleServiceLogger(
        minLevel: LogLevel.warning,
        out: out,
        err: err,
      ).info('dropped');
      expect(out.toString(), isEmpty);
    });

    test('routes info to out and errors/warnings to err', () {
      ConsoleServiceLogger(minLevel: LogLevel.debug, out: out, err: err)
        ..debug('a debug line')
        ..info('an info line')
        ..warning('a warning')
        ..error(
          'a failure',
          error: StateError('x'),
          stackTrace: StackTrace.current,
        );

      expect(out.toString(), contains('[DEBUG] a debug line'));
      expect(out.toString(), contains('[INFO] an info line'));
      expect(err.toString(), contains('[WARNING] a warning'));
      expect(err.toString(), contains('[ERROR] a failure'));
      expect(err.toString(), contains('error: Bad state: x'));
    });
  });
}
