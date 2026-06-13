import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceDriverFactory', () {
    test('builds the right driver per OS', () {
      expect(
        ServiceDriverFactory.forOperatingSystem('linux'),
        isA<LinuxSystemdDriver>(),
      );
      expect(
        ServiceDriverFactory.forOperatingSystem('macos'),
        isA<MacOsLaunchdDriver>(),
      );
      expect(
        ServiceDriverFactory.forOperatingSystem('windows'),
        isA<WindowsServiceDriver>(),
      );
    });

    test(
      'selects the Windows backend (SCM default, Task Scheduler opt-in)',
      () {
        expect(
          ServiceDriverFactory.forOperatingSystem('windows'),
          isA<WindowsServiceDriver>(),
        );
        expect(
          ServiceDriverFactory.forOperatingSystem(
            'windows',
            windowsBackend: WindowsServiceBackend.taskScheduler,
          ),
          isA<WindowsTaskSchedulerDriver>(),
        );
      },
    );

    test('throws on unsupported platforms', () {
      expect(
        () => ServiceDriverFactory.forOperatingSystem('plan9'),
        throwsA(isA<PlatformNotSupportedException>()),
      );
    });

    test('forCurrentPlatform returns a driver for the host', () {
      final driver = ServiceDriverFactory.forCurrentPlatform();
      expect(driver, isA<PlatformServiceDriver>());
    });
  });
}
