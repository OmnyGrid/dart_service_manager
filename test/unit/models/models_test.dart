import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceStatus', () {
    test('parses known names and falls back to unknown', () {
      expect(ServiceStatus.parse('running'), ServiceStatus.running);
      expect(ServiceStatus.parse('nonsense'), ServiceStatus.unknown);
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
