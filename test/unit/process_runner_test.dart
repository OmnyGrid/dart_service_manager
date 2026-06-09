import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessRunResult', () {
    test('succeeded reflects a zero exit code', () {
      expect(const ProcessRunResult(exitCode: 0).succeeded, isTrue);
      expect(const ProcessRunResult(exitCode: 1).succeeded, isFalse);
    });

    test('captures stdout and stderr', () {
      const result = ProcessRunResult(
        exitCode: 2,
        stdout: 'out',
        stderr: 'err',
      );
      expect(result.stdout, 'out');
      expect(result.stderr, 'err');
      expect(result.toString(), contains('2'));
    });
  });
}
