import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

void main() {
  UserSystemdStatus status({
    bool linger = true,
    bool bus = true,
    bool systemctl = true,
  }) => UserSystemdStatus(
    username: 'alice',
    uid: 1000,
    lingerEnabled: linger,
    userBusAvailable: bus,
    systemctlUserAvailable: systemctl,
    runtimeDirectory: '/run/user/1000',
    diagnostics: const ['user: alice (uid 1000)'],
    warnings: const ['fix me'],
  );

  test('ready requires systemctl + bus + linger', () {
    expect(status().ready, isTrue);
    expect(status(linger: false).ready, isFalse);
    expect(status(bus: false).ready, isFalse);
    expect(status(systemctl: false).ready, isFalse);
  });

  test('toJson exposes the fields and ready', () {
    final json = status().toJson();
    expect(json['username'], 'alice');
    expect(json['uid'], 1000);
    expect(json['runtimeDirectory'], '/run/user/1000');
    expect(json['ready'], isTrue);
    expect(json['warnings'], ['fix me']);
  });

  test('diagnostics and warnings are unmodifiable', () {
    expect(() => status().warnings.add('x'), throwsUnsupportedError);
    expect(() => status().diagnostics.add('x'), throwsUnsupportedError);
  });

  test('toString summarises the state', () {
    expect(status().toString(), contains('alice/1000'));
    expect(status().toString(), contains('ready: true'));
  });
}
