import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late JsonServiceRegistry registry;

  RegistryEntry entry(String pkg, String svc, {ServiceStatus? status}) =>
      RegistryEntry(
        packageName: pkg,
        serviceName: svc,
        platform: 'linux',
        scope: ServiceScope.user,
        binaryPath: '/bin/$pkg/$svc',
        installedAt: DateTime.utc(2026, 1, 1),
        status: status ?? ServiceStatus.installed,
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dsm_registry');
    registry = JsonServiceRegistry(p.join(dir.path, 'registry.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('returns empty when the file does not exist', () async {
    expect(await registry.all(), isEmpty);
    expect(await registry.packages(), isEmpty);
    expect(await registry.find('a', 'b'), isNull);
  });

  test('upsert persists and can be read back', () async {
    await registry.upsert(entry('analytics', 'worker'));
    final all = await registry.all();
    expect(all, hasLength(1));
    expect(all.single.qualifiedName, 'analytics:worker');
    expect(File(registry.filePath).existsSync(), isTrue);
  });

  test('upsert replaces an existing entry', () async {
    await registry.upsert(entry('a', 's'));
    await registry.upsert(entry('a', 's', status: ServiceStatus.running));
    final all = await registry.all();
    expect(all, hasLength(1));
    expect(all.single.status, ServiceStatus.running);
  });

  test('byPackage and packages group correctly', () async {
    await registry.upsert(entry('a', 's1'));
    await registry.upsert(entry('a', 's2'));
    await registry.upsert(entry('b', 's1'));
    expect(await registry.packages(), ['a', 'b']);
    expect(await registry.byPackage('a'), hasLength(2));
  });

  test('remove deletes a single entry', () async {
    await registry.upsert(entry('a', 's1'));
    await registry.upsert(entry('a', 's2'));
    await registry.remove('a', 's1');
    expect(await registry.byPackage('a'), hasLength(1));
    expect(await registry.find('a', 's1'), isNull);
  });

  test('survives a reopen (persisted JSON round-trip)', () async {
    await registry.upsert(entry('a', 's', status: ServiceStatus.running));
    final reopened = JsonServiceRegistry(registry.filePath);
    final found = await reopened.find('a', 's');
    expect(found, isNotNull);
    expect(found!.status, ServiceStatus.running);
    expect(found.installedAt, DateTime.utc(2026, 1, 1));
  });

  test('serialises concurrent upserts without losing data', () async {
    await Future.wait([
      for (var i = 0; i < 10; i++) registry.upsert(entry('a', 's$i')),
    ]);
    expect(await registry.all(), hasLength(10));
  });

  test('throws a registry exception on malformed JSON', () async {
    File(registry.filePath).writeAsStringSync('{ not json');
    expect(registry.all(), throwsA(isA<ServiceRegistryException>()));
  });
}
