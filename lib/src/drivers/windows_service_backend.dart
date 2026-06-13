/// Selects which Windows service mechanism the driver targets.
///
/// Windows has two ways to run a background program as a managed service, with
/// different trade-offs for a plain console executable:
///
/// - [serviceControlManager] — the classic SCM (`sc.exe`). "True" Windows
///   services with pause/resume, but a plain compiled executable that does not
///   implement a service control dispatcher is killed with error 1053. Suitable
///   when your entrypoint is wrapped in a service host.
/// - [taskScheduler] — a boot/logon-triggered Task Scheduler task
///   (`schtasks.exe`). Runs ordinary console programs as background daemons with
///   no dispatcher requirement; the right choice for the common "install my CLI
///   as a service" case. No true pause/resume.
enum WindowsServiceBackend {
  /// The Windows Service Control Manager (`sc.exe`).
  serviceControlManager,

  /// Windows Task Scheduler (`schtasks.exe`).
  taskScheduler,
}
