import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProcessRunResult', () {
    test('succeeded reflects a zero exit code', () {
      expect(const ProcessRunResult(exitCode: 0).succeeded, isTrue);
      expect(const ProcessRunResult(exitCode: 1).succeeded, isFalse);
    });

    test('captures stdout and stderr', () {
      const result = ProcessRunResult(
        exitCode: 2,
        stdout: 'out',
        stderr: 'err',
      );
      expect(result.stdout, 'out');
      expect(result.stderr, 'err');
      expect(result.toString(), contains('2'));
    });
  });

  group('SystemProcessRunner', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('dsm_runner'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('runs a real process and captures its result', () async {
      // Prints `<args>|<DSM_PROBE>|<cwd>` to stdout, `err` to stderr, exits 3.
      final script = File(p.join(dir.path, 'probe.dart'))
        ..writeAsStringSync(r'''
import 'dart:io';

void main(List<String> args) {
  stdout.write(
    '${args.join(',')}|${Platform.environment['DSM_PROBE']}'
    '|${Directory.current.path}',
  );
  stderr.write('err');
  exit(3);
}
''');
      final result = await const SystemProcessRunner().run(
        Platform.resolvedExecutable,
        [script.path, 'a b', 'c'],
        workingDirectory: dir.path,
        environment: {'DSM_PROBE': 'on'},
      );
      expect(result.exitCode, 3, reason: result.stderr);
      expect(result.succeeded, isFalse);
      final [args, env, cwd] = result.stdout.split('|');
      expect(args, 'a b,c'); // no shell: the space stays in one argument
      expect(env, 'on');
      expect(
        Directory(cwd).resolveSymbolicLinksSync(),
        dir.resolveSymbolicLinksSync(),
      );
      expect(result.stderr, 'err');
    });
  });
}
