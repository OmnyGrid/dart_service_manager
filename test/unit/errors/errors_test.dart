import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceManagerException', () {
    test('each subtype carries its stable code', () {
      expect(
        const ServiceInstallationException('x').code,
        ErrorCodes.installationFailed,
      );
      expect(
        const ServiceCompilationException('x').code,
        ErrorCodes.compilationFailed,
      );
      expect(const ServiceStartException('x').code, ErrorCodes.startFailed);
      expect(const ServiceStopException('x').code, ErrorCodes.stopFailed);
      expect(
        const ServiceRegistryException('x').code,
        ErrorCodes.registryError,
      );
      expect(
        const PlatformNotSupportedException('x').code,
        ErrorCodes.platformNotSupported,
      );
      expect(
        const ServiceManifestException('x').code,
        ErrorCodes.manifestError,
      );
      expect(const ServiceNotFoundException('x').code, ErrorCodes.notFound);
    });

    test('toString includes code and message', () {
      const ex = ServiceStartException('it broke');
      expect(ex.toString(), contains(ErrorCodes.startFailed));
      expect(ex.toString(), contains('it broke'));
    });

    test('preserves and renders the root cause', () {
      final cause = StateError('underlying');
      final ex = ServiceInstallationException('failed', cause: cause);
      expect(ex.cause, same(cause));
      expect(ex.toString(), contains('cause:'));
    });

    test('error codes are distinct and stable', () {
      final codes = {
        ErrorCodes.installationFailed,
        ErrorCodes.compilationFailed,
        ErrorCodes.startFailed,
        ErrorCodes.stopFailed,
        ErrorCodes.registryError,
        ErrorCodes.platformNotSupported,
        ErrorCodes.manifestError,
        ErrorCodes.notFound,
      };
      expect(codes, hasLength(8));
    });

    test('is exhaustively matchable as a sealed type', () {
      const ServiceManagerException ex = ServiceStopException('x');
      final label = switch (ex) {
        ServiceInstallationException() => 'install',
        ServiceCompilationException() => 'compile',
        ServiceStartException() => 'start',
        ServiceStopException() => 'stop',
        ServiceRegistryException() => 'registry',
        PlatformNotSupportedException() => 'platform',
        ServiceManifestException() => 'manifest',
        ServiceNotFoundException() => 'notfound',
        PermissionDeniedException() => 'permission',
        ServiceAlreadyInstalledException() => 'already',
      };
      expect(label, 'stop');
    });

    test('new subtypes carry their codes', () {
      expect(
        const PermissionDeniedException('x').code,
        ErrorCodes.permissionDenied,
      );
      expect(
        const ServiceAlreadyInstalledException('x').code,
        ErrorCodes.alreadyInstalled,
      );
    });
  });
}
