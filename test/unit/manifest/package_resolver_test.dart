import 'dart:convert';
import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dsm_resolve'));
  tearDown(() => root.deleteSync(recursive: true));

  Directory packageDir(String name) {
    final dir = Directory(p.join(root.path, name))..createSync();
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: $name\n');
    return dir;
  }

  test('uses an explicit path when provided', () async {
    final pkg = packageDir('alpha');
    final resolver = PackageResolver(workingDirectory: root);
    expect(await resolver.resolve('alpha', path: pkg.path), pkg.path);
  });

  test('throws when the explicit path has no pubspec', () {
    final resolver = PackageResolver(workingDirectory: root);
    expect(
      () => resolver.resolve('alpha', path: root.path),
      throwsA(isA<ServiceNotFoundException>()),
    );
  });

  test('resolves the current directory when its name matches', () async {
    final pkg = packageDir('beta');
    final resolver = PackageResolver(workingDirectory: pkg);
    expect(p.equals(await resolver.resolve('beta'), pkg.path), isTrue);
  });

  test('resolves via package_config.json', () async {
    final pkg = packageDir('gamma');
    final workspace = Directory(p.join(root.path, 'app'))..createSync();
    final dartTool = Directory(p.join(workspace.path, '.dart_tool'))
      ..createSync();
    File(p.join(dartTool.path, 'package_config.json')).writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'gamma', 'rootUri': Uri.file(pkg.path).toString()},
        ],
      }),
    );
    final resolver = PackageResolver(workingDirectory: workspace);
    expect(p.equals(await resolver.resolve('gamma'), pkg.path), isTrue);
  });

  test('throws when the package cannot be resolved', () {
    final resolver = PackageResolver(workingDirectory: root);
    expect(
      () => resolver.resolve('missing'),
      throwsA(isA<ServiceNotFoundException>()),
    );
  });
}
