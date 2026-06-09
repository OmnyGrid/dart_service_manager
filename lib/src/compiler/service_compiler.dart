import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/service_exception.dart';
import '../logging/service_logger.dart';
import '../process/process_runner.dart';

/// Compiles Dart service entrypoints to self-contained native executables via
/// `dart compile exe`, caching the output under a managed binaries directory.
///
/// The compiler is incremental: it skips recompilation when an up-to-date
/// executable already exists (the binary is newer than the source script),
/// unless [force] is requested.
final class ServiceCompiler {
  /// The directory compiled binaries are written to.
  final String outputDirectory;

  /// The process runner used to invoke the Dart toolchain.
  final ProcessRunner processRunner;

  /// The Dart executable to invoke (defaults to the running `dart`).
  final String dartExecutable;

  /// The logger for compilation progress.
  final ServiceLogger logger;

  /// Creates a service compiler writing binaries into [outputDirectory].
  ServiceCompiler({
    required this.outputDirectory,
    required this.processRunner,
    this.logger = const SilentServiceLogger(),
    String? dartExecutable,
  }) : dartExecutable = dartExecutable ?? _defaultDartExecutable();

  /// Compiles [scriptPath] (resolved against [packageRoot]) into a native
  /// executable for the service named [packageName]/[serviceName].
  ///
  /// Returns the compiled [File]. When [force] is `false` and a fresh
  /// executable already exists, compilation is skipped and the cached binary is
  /// returned.
  ///
  /// Throws [ServiceCompilationException] if the source is missing or
  /// `dart compile exe` fails.
  Future<File> compileService({
    required String packageName,
    required String serviceName,
    required String packageRoot,
    required String scriptPath,
    bool force = false,
  }) async {
    final source = File(p.normalize(p.join(packageRoot, scriptPath)));
    if (!source.existsSync()) {
      throw ServiceCompilationException(
        "Service entrypoint '$scriptPath' not found at ${source.path}.",
      );
    }

    final output = File(_outputPathFor(packageName, serviceName));
    if (!force && _isUpToDate(source, output)) {
      logger.debug('Reusing up-to-date binary ${output.path}');
      return output;
    }

    Directory(outputDirectory).createSync(recursive: true);
    logger.info('Compiling ${source.path} -> ${output.path}');

    final result = await processRunner.run(dartExecutable, [
      'compile',
      'exe',
      source.path,
      '-o',
      output.path,
    ], workingDirectory: packageRoot);

    if (!result.succeeded || !output.existsSync()) {
      throw ServiceCompilationException(
        'Failed to compile $scriptPath (exit ${result.exitCode}): '
        '${result.stderr.trim().isEmpty ? result.stdout.trim() : result.stderr.trim()}',
      );
    }
    return output;
  }

  /// The path a compiled binary for [packageName]/[serviceName] is stored at,
  /// including the platform-appropriate executable extension.
  String _outputPathFor(String packageName, String serviceName) {
    final ext = Platform.isWindows ? '.exe' : '';
    return p.join(outputDirectory, '${packageName}_$serviceName$ext');
  }

  bool _isUpToDate(File source, File output) {
    if (!output.existsSync()) return false;
    return output.statSync().modified.isAfter(source.statSync().modified) ||
        output.statSync().modified == source.statSync().modified;
  }

  static String _defaultDartExecutable() => Platform.resolvedExecutable;
}
