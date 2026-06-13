import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceStatus', () {
    test('parses known names and falls back to unknown', () {
      expect(ServiceStatus.parse('running'), ServiceStatus.running);
      expect(ServiceStatus.parse('nonsense'), ServiceStatus.unknown);
    });
  });

  group('RestartPolicy', () {
    test('parses names and aliases', () {
      expect(RestartPolicy.tryParse('always'), RestartPolicy.always);
      expect(RestartPolicy.tryParse('on-failure'), RestartPolicy.onFailure);
      expect(RestartPolicy.tryParse('on_failure'), RestartPolicy.onFailure);
      expect(RestartPolicy.tryParse('onFailure'), RestartPolicy.onFailure);
      expect(RestartPolicy.tryParse('never'), RestartPolicy.never);
      expect(RestartPolicy.tryParse('whatever'), isNull);
    });
  });

  group('ServiceDescriptor policy', () {
    test('defaults match the pre-policy behaviour', () {
      final d = ServiceDescriptor(
        packageName: 'p',
        serviceName: 's',
        executablePath: '/bin/s',
      );
      expect(d.restart, RestartPolicy.always);
      expect(d.restartDelay, const Duration(seconds: 5));
      expect(d.autoStart, isTrue);
      expect(d.workingDirectory, isNull);
      expect(d.stopTimeout, isNull);
      expect(d.environmentFile, isNull);
    });

    test('copyWith replaces policy fields', () {
      final d =
          ServiceDescriptor(
            packageName: 'p',
            serviceName: 's',
            executablePath: '/bin/s',
          ).copyWith(
            restart: RestartPolicy.onFailure,
            autoStart: false,
            workingDirectory: '/srv',
            environmentFile: '/etc/s.env',
          );
      expect(d.restart, RestartPolicy.onFailure);
      expect(d.autoStart, isFalse);
      expect(d.workingDirectory, '/srv');
      expect(d.environmentFile, '/etc/s.env');
    });
  });

  group('ServiceDescriptor.resolveSelfExecutable', () {
    test('AOT binary uses the binary and args as-is', () {
      final r = ServiceDescriptor.resolveSelfExecutable(
        resolvedExecutable: '/usr/local/bin/myapp',
        script: '/proj/bin/main.dart',
        arguments: ['hub', 'start'],
      );
      expect(r.executable, '/usr/local/bin/myapp');
      expect(r.arguments, ['hub', 'start']);
    });

    test('JIT (dart VM) prepends the script', () {
      final r = ServiceDescriptor.resolveSelfExecutable(
        resolvedExecutable: '/opt/dart-sdk/bin/dart',
        script: '/proj/bin/main.dart',
        arguments: ['hub', 'start'],
      );
      expect(r.executable, '/opt/dart-sdk/bin/dart');
      expect(r.arguments, ['/proj/bin/main.dart', 'hub', 'start']);
    });

    test('dart VM without a known script falls back to args only', () {
      final r = ServiceDescriptor.resolveSelfExecutable(
        resolvedExecutable: r'C:\dart\bin\dart.exe',
        arguments: ['x'],
      );
      expect(r.arguments, ['x']);
    });

    test('JIT does not double a script already leading the arguments', () {
      const script = '/proj/bin/main.dart';
      final r = ServiceDescriptor.resolveSelfExecutable(
        resolvedExecutable: '/opt/dart-sdk/bin/dart',
        script: script,
        arguments: [script, 'hub', 'start'],
      );
      expect(r.executable, '/opt/dart-sdk/bin/dart');
      expect(r.arguments, [script, 'hub', 'start']);
      expect(r.arguments.where((a) => a == script), hasLength(1));
    });

    test('JIT idempotency holds on Windows dart.exe too', () {
      const script = r'C:\pkg\bin\main.dart-3.12.1.snapshot';
      final r = ServiceDescriptor.resolveSelfExecutable(
        resolvedExecutable: r'C:\dart\bin\dart.exe',
        script: script,
        arguments: [script, 'hub', 'start'],
      );
      expect(r.executable, r'C:\dart\bin\dart.exe');
      expect(r.arguments, [script, 'hub', 'start']);
      expect(r.arguments.where((a) => a == script), hasLength(1));
    });
  });

  group('ServiceScope', () {
    test('tryParse handles known and unknown values', () {
      expect(ServiceScope.tryParse('system'), ServiceScope.system);
      expect(ServiceScope.tryParse('user'), ServiceScope.user);
      expect(ServiceScope.tryParse('nope'), isNull);
    });
  });

  group('DartPackageService', () {
    final service = const DartPackageService(
      packageName: 'analytics',
      serviceName: 'worker',
      executablePath: '/bin/worker',
      status: ServiceStatus.running,
    );

    test('exposes the qualified name', () {
      expect(service.qualifiedName, 'analytics:worker');
    });

    test('round-trips through JSON', () {
      final json = service.toJson();
      expect(DartPackageService.fromJson(json), service);
    });

    test('copyWith replaces the status', () {
      expect(
        service.copyWith(status: ServiceStatus.stopped).status,
        ServiceStatus.stopped,
      );
    });

    test('supports structural equality', () {
      expect(service, isNot(service.copyWith(status: ServiceStatus.failed)));
      expect(service.hashCode, isA<int>());
      expect(service.toString(), contains('analytics:worker'));
    });
  });

  group('ServiceDescriptor', () {
    test('derives platform-specific identifiers and sanitises names', () {
      final descriptor = ServiceDescriptor(
        packageName: 'analytics.server',
        serviceName: 'web-worker',
        executablePath: '/opt/bin/worker',
      );
      expect(descriptor.systemName, 'dart_analytics_server_web_worker');
      expect(
        descriptor.launchdLabel,
        'com.dartservices.analytics_server.web_worker',
      );
      expect(descriptor.qualifiedName, 'analytics.server:web-worker');
      expect(descriptor.description, contains('web-worker'));
    });

    test('uses the provided description when given', () {
      final descriptor = ServiceDescriptor(
        packageName: 'p',
        serviceName: 's',
        executablePath: '/x',
        description: 'Custom',
      );
      expect(descriptor.description, 'Custom');
    });
  });

  group('ServiceInstallConfig', () {
    test('copyWith updates script and scope', () {
      const config = ServiceInstallConfig(
        packageName: 'p',
        serviceName: 's',
        scriptPath: 'bin/s.dart',
      );
      final updated = config.copyWith(
        scriptPath: '/abs/s.dart',
        scope: ServiceScope.system,
      );
      expect(updated.scriptPath, '/abs/s.dart');
      expect(updated.scope, ServiceScope.system);
      expect(config.toString(), contains('p:s'));
    });
  });
}
