import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

import '../../support/fake_process_runner.dart';

void main() {
  /// Builds a runner that simulates a Linux systemd host. Each knob tweaks one
  /// probe so a test can isolate a single condition.
  FakeProcessRunner systemdHost({
    bool hasSystemctl = true,
    bool hasLoginctl = true,
    String username = 'alice',
    String uid = '1000',
    bool linger = true,
    bool enableLingerSucceeds = true,
    String busStderr = '',
  }) {
    return FakeProcessRunner(
      responder: (run) {
        final cl = run.commandLine;
        if (run.executable == 'sh') {
          if (cl.contains('command -v systemctl')) {
            return ProcessRunResult(exitCode: hasSystemctl ? 0 : 1);
          }
          if (cl.contains('command -v loginctl')) {
            return ProcessRunResult(exitCode: hasLoginctl ? 0 : 1);
          }
        }
        if (run.executable == 'id') {
          if (run.args.contains('-un')) {
            return ProcessRunResult(exitCode: 0, stdout: '$username\n');
          }
          if (run.args.contains('-u')) {
            return ProcessRunResult(exitCode: 0, stdout: '$uid\n');
          }
        }
        if (run.executable == 'loginctl' && run.args.contains('show-user')) {
          return ProcessRunResult(
            exitCode: 0,
            stdout: 'Linger=${linger ? 'yes' : 'no'}\n',
          );
        }
        if (run.executable == 'sudo' && cl.contains('enable-linger')) {
          return ProcessRunResult(
            exitCode: enableLingerSucceeds ? 0 : 1,
            stderr: enableLingerSucceeds ? '' : 'sudo: a password is required',
          );
        }
        if (run.executable == 'systemctl' && run.args.contains('status')) {
          return ProcessRunResult(
            exitCode: busStderr.isEmpty ? 0 : 1,
            stderr: busStderr,
          );
        }
        return const ProcessRunResult(exitCode: 0);
      },
    );
  }

  UserSystemdManager manager(
    FakeProcessRunner runner, {
    Map<String, String>? environment,
  }) => UserSystemdManager(
    runner: runner,
    operatingSystem: 'linux',
    environment: environment ?? const {},
  );

  test('happy path: linger on, bus reachable -> ready, no warnings', () async {
    final runner = systemdHost();
    final status = await manager(runner).ensurePersistentUserSystemd();

    expect(status.username, 'alice');
    expect(status.uid, 1000);
    expect(status.lingerEnabled, isTrue);
    expect(status.userBusAvailable, isTrue);
    expect(status.systemctlUserAvailable, isTrue);
    expect(status.ready, isTrue);
    expect(status.warnings, isEmpty);
    // Idempotent: no enable-linger issued when already enabled.
    expect(
      runner.runs.any((r) => r.commandLine.contains('enable-linger')),
      isFalse,
    );
  });

  test('resolves /run/user/<uid> when XDG_RUNTIME_DIR is absent', () async {
    final runner = systemdHost(uid: '1000');
    final status = await manager(runner).ensurePersistentUserSystemd();
    expect(status.runtimeDirectory, '/run/user/1000');
    // The bus probe runs with that XDG_RUNTIME_DIR.
    final probe = runner.runs.firstWhere((r) => r.args.contains('status'));
    expect(probe.environment, {'XDG_RUNTIME_DIR': '/run/user/1000'});
  });

  test('uses XDG_RUNTIME_DIR from the environment when set', () async {
    final status = await manager(
      systemdHost(),
      environment: {'XDG_RUNTIME_DIR': '/run/user/42'},
    ).ensurePersistentUserSystemd();
    expect(status.runtimeDirectory, '/run/user/42');
  });

  group('lingering', () {
    test('enables it via sudo -n when disabled', () async {
      final runner = systemdHost(linger: false);
      final status = await manager(runner).ensurePersistentUserSystemd();
      expect(status.lingerEnabled, isTrue);
      expect(
        runner.runs.any(
          (r) => r.commandLine == 'sudo -n loginctl enable-linger alice',
        ),
        isTrue,
      );
      expect(status.warnings, isEmpty);
    });

    test('warns with the manual command when sudo cannot enable it', () async {
      final status = await manager(
        systemdHost(linger: false, enableLingerSucceeds: false),
      ).ensurePersistentUserSystemd();
      expect(status.lingerEnabled, isFalse);
      expect(
        status.warnings.join('\n'),
        contains('sudo loginctl enable-linger alice'),
      );
    });

    test('does not attempt to enable when enableLinger is false', () async {
      final runner = systemdHost(linger: false);
      final status = await manager(
        runner,
      ).ensurePersistentUserSystemd(enableLinger: false);
      expect(status.lingerEnabled, isFalse);
      expect(
        runner.runs.any((r) => r.commandLine.contains('enable-linger')),
        isFalse,
      );
    });
  });

  group('user bus failures', () {
    for (final message in const [
      'Failed to connect to bus: No medium found',
      'Failed to connect to bus: No such file or directory',
      'Failed to connect to bus: Connection refused',
    ]) {
      test('detects "$message"', () async {
        final status = await manager(
          systemdHost(busStderr: '$message\n'),
        ).ensurePersistentUserSystemd();
        expect(status.userBusAvailable, isFalse);
        expect(status.ready, isFalse);
        expect(status.warnings.join('\n'), contains(message));
      });
    }

    test('detects a generic bus failure line', () async {
      final status = await manager(
        systemdHost(busStderr: 'Failed to connect to bus: weird error\n'),
      ).ensurePersistentUserSystemd();
      expect(status.userBusAvailable, isFalse);
    });
  });

  group('missing tools', () {
    test(
      'systemctl missing -> systemctlUserAvailable false + warning',
      () async {
        final status = await manager(
          systemdHost(hasSystemctl: false),
        ).ensurePersistentUserSystemd();
        expect(status.systemctlUserAvailable, isFalse);
        expect(status.userBusAvailable, isFalse);
        expect(status.warnings.join('\n'), contains('systemctl not found'));
      },
    );

    test('loginctl missing -> warning, lingering left undetermined', () async {
      final runner = systemdHost(hasLoginctl: false);
      final status = await manager(runner).ensurePersistentUserSystemd();
      expect(status.lingerEnabled, isFalse);
      expect(status.warnings.join('\n'), contains('loginctl not found'));
      expect(runner.runs.any((r) => r.args.contains('show-user')), isFalse);
    });
  });

  test('throws PlatformNotSupportedException off Linux', () {
    final mgr = UserSystemdManager(
      runner: systemdHost(),
      operatingSystem: 'macos',
      environment: const {},
    );
    expect(
      mgr.ensurePersistentUserSystemd,
      throwsA(isA<PlatformNotSupportedException>()),
    );
  });

  test(
    'resolveRuntimeDirectory prefers env, falls back to /run/user',
    () async {
      expect(
        await manager(
          systemdHost(),
          environment: {'XDG_RUNTIME_DIR': '/run/user/7'},
        ).resolveRuntimeDirectory(),
        '/run/user/7',
      );
      expect(
        await manager(systemdHost(uid: '1000')).resolveRuntimeDirectory(),
        '/run/user/1000',
      );
    },
  );
}
