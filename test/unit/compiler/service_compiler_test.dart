import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/fake_process_runner.dart';

void main() {
  late Directory root;
  late Directory packageRoot;
  late Directory outputDir;

  /// A fake `dart compile` that creates the requested `-o` output file.
  FakeProcessRunner compilingRunner({int exitCode = 0}) => FakeProcessRunner(
    responder: (run) {
      if (exitCode == 0) {
        final idx = run.args.indexOf('-o');
        File(run.args[idx + 1]).writeAsStringSync('#!fake-binary');
      }
      return ProcessRunResult(exitCode: exitCode, stderr: 'compile error');
    },
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('dsm_compiler');
    packageRoot = Directory(p.join(root.path, 'pkg'))..createSync();
    Directory(p.join(packageRoot.path, 'bin')).createSync();
    File(
      p.join(packageRoot.path, 'bin', 'worker.dart'),
    ).writeAsStringSync('void main() {}');
    outputDir = Directory(p.join(root.path, 'out'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  ServiceCompiler compiler(FakeProcessRunner runner) => ServiceCompiler(
    outputDirectory: outputDir.path,
    processRunner: runner,
    dartExecutable: 'dart',
  );

  test('compiles the entrypoint and returns the binary', () async {
    final runner = compilingRunner();
    final binary = await compiler(runner).compileService(
      packageName: 'pkg',
      serviceName: 'worker',
      packageRoot: packageRoot.path,
      scriptPath: 'bin/worker.dart',
    );
    expect(binary.existsSync(), isTrue);
    expect(runner.last.executable, 'dart');
    expect(runner.last.args, containsAllInOrder(['compile', 'exe']));
  });

  test('skips recompilation when the binary is up to date', () async {
    final runner = compilingRunner();
    final c = compiler(runner);
    await c.compileService(
      packageName: 'pkg',
      serviceName: 'worker',
      packageRoot: packageRoot.path,
      scriptPath: 'bin/worker.dart',
    );
    await c.compileService(
      packageName: 'pkg',
      serviceName: 'worker',
      packageRoot: packageRoot.path,
      scriptPath: 'bin/worker.dart',
    );
    expect(runner.runs, hasLength(1));
  });

  test('force recompiles even when up to date', () async {
    final runner = compilingRunner();
    final c = compiler(runner);
    await c.compileService(
      packageName: 'pkg',
      serviceName: 'worker',
      packageRoot: packageRoot.path,
      scriptPath: 'bin/worker.dart',
    );
    await c.compileService(
      packageName: 'pkg',
      serviceName: 'worker',
      packageRoot: packageRoot.path,
      scriptPath: 'bin/worker.dart',
      force: true,
    );
    expect(runner.runs, hasLength(2));
  });

  test('throws when the source script is missing', () {
    expect(
      () => compiler(compilingRunner()).compileService(
        packageName: 'pkg',
        serviceName: 'worker',
        packageRoot: packageRoot.path,
        scriptPath: 'bin/missing.dart',
      ),
      throwsA(isA<ServiceCompilationException>()),
    );
  });

  test('throws when dart compile fails', () {
    expect(
      () => compiler(compilingRunner(exitCode: 1)).compileService(
        packageName: 'pkg',
        serviceName: 'worker',
        packageRoot: packageRoot.path,
        scriptPath: 'bin/worker.dart',
      ),
      throwsA(isA<ServiceCompilationException>()),
    );
  });
}
