import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

import '../../support/fake_process_runner.dart';

void main() {
  group('SystemPrivilegeChecker (POSIX)', () {
    test('elevated when id -u prints 0', () async {
      final checker = SystemPrivilegeChecker(
        operatingSystemOverride: 'linux',
        runner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(exitCode: 0, stdout: '0\n'),
        ),
      );
      expect(await checker.isElevated(), isTrue);
    });

    test('not elevated for a non-zero uid', () async {
      final checker = SystemPrivilegeChecker(
        operatingSystemOverride: 'macos',
        runner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(exitCode: 0, stdout: '501\n'),
        ),
      );
      expect(await checker.isElevated(), isFalse);
    });

    test('runs `id -u`', () async {
      final runner = FakeProcessRunner(
        defaultResult: const ProcessRunResult(exitCode: 0, stdout: '0'),
      );
      await SystemPrivilegeChecker(
        operatingSystemOverride: 'linux',
        runner: runner,
      ).isElevated();
      expect(runner.last.commandLine, 'id -u');
    });

    test('falls back to SUDO_UID when id is unavailable', () async {
      final checker = SystemPrivilegeChecker(
        operatingSystemOverride: 'linux',
        environmentOverride: {'SUDO_UID': '0'},
        runner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(exitCode: 127, stderr: 'no id'),
        ),
      );
      expect(await checker.isElevated(), isTrue);
    });

    test('not elevated when id fails and no SUDO_UID', () async {
      final checker = SystemPrivilegeChecker(
        operatingSystemOverride: 'linux',
        environmentOverride: const {},
        runner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(exitCode: 127),
        ),
      );
      expect(await checker.isElevated(), isFalse);
    });
  });

  group('SystemPrivilegeChecker (Windows)', () {
    test('elevated when `net session` succeeds', () async {
      final runner = FakeProcessRunner(
        defaultResult: const ProcessRunResult(exitCode: 0),
      );
      final checker = SystemPrivilegeChecker(
        operatingSystemOverride: 'windows',
        runner: runner,
      );
      expect(await checker.isElevated(), isTrue);
      expect(runner.last.commandLine, 'net session');
    });

    test('not elevated when `net session` fails', () async {
      final checker = SystemPrivilegeChecker(
        operatingSystemOverride: 'windows',
        runner: FakeProcessRunner(
          defaultResult: const ProcessRunResult(exitCode: 2, stderr: 'denied'),
        ),
      );
      expect(await checker.isElevated(), isFalse);
    });
  });
}
