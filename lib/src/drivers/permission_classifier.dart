import '../process/process_runner.dart';

/// Heuristically detects whether a failed process [result] indicates a
/// privilege/permission problem (so drivers can raise
/// `PermissionDeniedException` instead of a generic failure).
///
/// Matches the common stderr phrasing from `systemctl`/`launchctl`/`sc.exe`
/// and the Windows `ERROR_ACCESS_DENIED` (5) exit code.
bool isPermissionFailure(ProcessRunResult result) {
  final stderr = result.stderr.toLowerCase();
  const needles = [
    'permission denied',
    'access is denied',
    'must be root',
    'must be superuser',
    'not authorized',
    'insufficient privilege',
    'requires root',
    'authentication is required',
    'interactive authentication required',
    'operation not permitted',
  ];
  if (needles.any(stderr.contains)) return true;
  return result.exitCode == 5; // Windows ERROR_ACCESS_DENIED
}
