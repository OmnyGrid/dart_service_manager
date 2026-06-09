# dart_service_manager

[![pub package](https://img.shields.io/pub/v/dart_service_manager.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/dart_service_manager)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Dart CI](https://github.com/OmnyGrid/dart_service_manager/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/OmnyGrid/dart_service_manager/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/OmnyGrid/dart_service_manager?logo=git&logoColor=white)](https://github.com/OmnyGrid/dart_service_manager/releases)
[![New Commits](https://img.shields.io/github/commits-since/OmnyGrid/dart_service_manager/latest?logo=git&logoColor=white)](https://github.com/OmnyGrid/dart_service_manager/network)
[![Last Commits](https://img.shields.io/github/last-commit/OmnyGrid/dart_service_manager?logo=git&logoColor=white)](https://github.com/OmnyGrid/dart_service_manager/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/OmnyGrid/dart_service_manager?logo=github&logoColor=white)](https://github.com/OmnyGrid/dart_service_manager/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/OmnyGrid/dart_service_manager?logo=github&logoColor=white)](https://github.com/OmnyGrid/dart_service_manager)
[![License](https://img.shields.io/github/license/OmnyGrid/dart_service_manager?logo=open-source-initiative&logoColor=green)](https://github.com/OmnyGrid/dart_service_manager/blob/master/LICENSE)

Declare services in a Dart package, compile them to native executables, and
install and manage them as **native operating-system services** — on Linux
(systemd), macOS (launchd) and Windows (Service Control Manager) — through a
first-class Dart API and a thin `dart-service` CLI.

It is a **library first**: the CLI is a small wrapper over the public
`DartServiceManager` API, the platform-specific code sits behind a single
driver abstraction, and every external process call is injectable, so the whole
thing is testable without touching a real init system.

```text
+-----------------------+
| CLI (dart-service)    |
+-----------------------+
            |
            v
+-----------------------+
| DartServiceManager    |   orchestration only
+-----------------------+
            |
            v
+-----------------------+
| PlatformServiceDriver |
+-----------------------+
      |      |      |
      v      v      v
   Linux  macOS  Windows
  systemd launchd  SCM
```

## Features

- **Declarative manifest** — list services in your package's `pubspec.yaml`.
- **Native compilation** — `dart compile exe`, cached and rebuilt on change.
- **Full lifecycle** — install, uninstall, start, stop, pause, resume, restart.
- **Status & inventory** — query live status; list services, packages, and a
  package's services.
- **Cross-platform** — systemd, launchd and Windows SCM behind one interface.
- **User or system scope** — per-user (no elevation, the default) or machine-wide.
- **Own registry** — a persistent, atomically-written JSON registry behind a
  repository abstraction, independent of OS discovery.
- **Clean, typed API** — sealed exceptions with stable codes, injectable
  structured logging, immutable value objects, constructor DI throughout.

## Platform support

| Capability | Linux (systemd) | macOS (launchd) | Windows (SCM) |
|------------|:---------------:|:---------------:|:-------------:|
| install / uninstall | ✅ | ✅ | ✅ |
| start / stop / restart | ✅ | ✅ | ✅ |
| status | ✅ | ✅ | ✅ |
| pause / resume | ➖ not supported | ➖ not supported | ✅ |

Pausing is only meaningful on Windows; on Linux and macOS `pause`/`resume`
throw `PlatformNotSupportedException`.

> **Windows note:** a plain compiled Dart executable does not implement a
> Windows service control dispatcher, so the SCM may report it as slow to
> respond to control requests. Wrapping the entrypoint in a service host makes
> control signals fully honoured.

## Declaring services

Add a `dart_services:` section to the target package's `pubspec.yaml`:

```yaml
name: analytics_server

dart_services:
  # Shorthand: service name -> entrypoint script.
  worker: bin/worker.dart

  # Map form: description, args and env are optional.
  scheduler:
    script: bin/scheduler.dart
    description: Periodic job scheduler
    args: ['--interval', '60']
    env:
      LOG_LEVEL: info

  monitor: bin/monitor.dart
```

A service entry may also reference a **pre-built `executable:`** instead of a
`script:` (skipping compilation), and set runtime policy: `workingDirectory`,
`restart` (`always`/`on-failure`/`never`), `restartDelay`, `autoStart`,
`stopTimeout`, and `envFile`:

```yaml
dart_services:
  api:
    executable: build/api          # already-built binary, not compiled
    args: ['--port', '8080']
    restart: on-failure
    restartDelay: 10
    autoStart: true
    envFile: /etc/api.env           # systemd EnvironmentFile=
```

See [`example/sample_package`](example/sample_package) for a runnable package, or
[`example/shelf_server`](example/shelf_server) for a real Shelf HTTP server managed as a service.

## Requirements

- **Dart SDK 3.x** — required on the machine that installs services, since
  entrypoints are compiled with `dart compile exe`.
- **Privileges** — `ServiceScope.user` (the default) needs none; `system` scope
  requires root (Linux/macOS) or Administrator (Windows). `install` warns if you
  run it elevated with the default user scope (a common `sudo` mistake), or
  request `--system` without elevation. Use `--system` as a shorthand for
  `--scope system`.
- **Per platform** — systemd (Linux), launchd (macOS) or the Service Control
  Manager (Windows), all present by default on their respective OSes.

> **Linux user services & persistence.** A user-scoped service runs under
> `systemctl --user`, which needs a per-user systemd bus and **lingering**
> (`loginctl enable-linger`) to keep running after logout and start at boot.
> `install` detects this automatically (resolving `XDG_RUNTIME_DIR`, validating
> the user bus, and trying `sudo loginctl enable-linger` non-interactively). If
> it cannot enable lingering itself it proceeds and warns with the exact command
> to run. You can also drive it directly via `UserSystemdManager`
> (`ensurePersistentUserSystemd()`), which returns a detailed `UserSystemdStatus`.

## Getting started

```yaml
# pubspec.yaml
dev_dependencies:
  dart_service_manager: ^1.3.0
```

```bash
dart pub get
# install the CLI globally (optional)
dart pub global activate dart_service_manager
```

## Usage — CLI

```bash
# Install all services of a package (resolved from the cwd or package_config).
dart-service install analytics_server

# Install one service, system-wide, from an explicit path.
dart-service --scope system install analytics_server:worker --path ./analytics_server

# Install an already-built executable as a service (args after `--`).
dart-service install myapp:hub --executable /usr/local/bin/myapp \
  --restart on-failure --env-file /etc/myapp/hub.env -- hub start

# Preview the generated unit/plist without installing.
dart-service install myapp:hub --executable /usr/local/bin/myapp --dry-run -- hub start

# Lifecycle.
dart-service start   analytics_server:worker
dart-service status  analytics_server:worker
dart-service restart analytics_server:worker
dart-service stop    analytics_server:worker

# Inventory.
dart-service list
dart-service packages
dart-service services analytics_server

# Remove one service, or every service of the package.
dart-service uninstall analytics_server:worker   # just the worker
dart-service uninstall analytics_server          # all services of the package
```

> A bare `package` reference (no `:service`) targets **every** service the
> package installed — this works for `install`, `start`, `stop`, `pause`,
> `resume`, `restart` and `uninstall`. Use `package:service` to target one.
> Uninstalling also deletes each service's cached native binary.

Full command reference: [`doc/cli.md`](doc/cli.md).

## Usage — Dart API

```dart
import 'package:dart_service_manager/dart_service_manager.dart';

Future<void> main() async {
  final manager = DartServiceManager.forCurrentPlatform(
    logger: ConsoleServiceLogger(),
  );

  // Compile + install every declared service.
  await manager.install('analytics_server');

  // Or a single service, system-wide.
  await manager.install(
    'analytics_server',
    serviceName: 'worker',
    scope: ServiceScope.system,
  );

  await manager.start('analytics_server', 'worker');

  final status = await manager.status('analytics_server', 'worker');
  print('worker is ${status.name}'); // running

  for (final service in await manager.listServices()) {
    print('${service.qualifiedName}: ${service.status.name}');
  }

  await manager.stop('analytics_server', 'worker');
  await manager.uninstall('analytics_server');
}
```

### Installing an existing executable (imperative)

Install an already-built binary — including the **currently running program** —
as a service, with explicit arguments, environment and runtime policy, without a
manifest or compilation. This is the path for a CLI that installs itself:

```dart
final descriptor = ServiceDescriptor.forCurrentExecutable(
  packageName: 'myapp',
  serviceName: 'hub',
  arguments: ['hub', 'start', '--config', '/etc/myapp/hub.yaml'],
  scope: ServiceScope.system,
  restart: RestartPolicy.onFailure,
  environmentFile: '/etc/myapp/hub.env', // systemd; secrets stay out of the unit
);

// Preview the generated unit/plist without touching the system:
print(manager.renderDefinition(descriptor));

await manager.installDescriptor(descriptor, startNow: true);
// later, change flags and re-apply (preserves running state):
await manager.reconfigure(descriptor.copyWith(arguments: ['hub', 'start', '-v']));
```

### Core API

```dart
Future<void> install(String package, {String? serviceName, ServiceScope scope = ServiceScope.user, String? path, bool force = false});
Future<void> installDescriptor(ServiceDescriptor descriptor, {bool startNow = false, bool force = false});
Future<void> reconfigure(ServiceDescriptor descriptor);
String renderDefinition(ServiceDescriptor descriptor);
Future<void> uninstall(String package, {String? serviceName});
Future<void> start(String package, String service);
Future<void> stop(String package, String service);
Future<void> pause(String package, String service);
Future<void> resume(String package, String service);
Future<void> restart(String package, String service);
Future<ServiceStatus> status(String package, String service);
Future<List<DartPackageService>> listServices();
Future<List<String>> listPackages();
Future<List<DartPackageService>> listPackageServices(String packageName);
```

Every dependency is constructor-injectable for embedding and testing — see the
default `DartServiceManager` constructor versus `DartServiceManager.forCurrentPlatform`.

## Where things are stored

| Platform | Registry & binaries |
|----------|---------------------|
| Linux | `$XDG_DATA_HOME` or `~/.local/share/dart_service_manager/` |
| macOS | `~/Library/Application Support/dart_service_manager/` |
| Windows | `%LOCALAPPDATA%\dart_service_manager\` |

Generated unit files / plists live in the per-scope OS locations
(`~/.config/systemd/user`, `~/Library/LaunchAgents`, `/etc/systemd/system`,
`/Library/LaunchDaemons`).

## Architecture

A short tour is in [`doc/architecture.md`](doc/architecture.md). In brief: the
CLI calls `DartServiceManager`, which composes a `ManifestLoader` +
`PackageResolver`, a `ServiceCompiler`, a `ServiceRegistry`, and a
`PlatformServiceDriver` — all wired over an injectable `ProcessRunner`.

## Running tests

```bash
dart test                      # unit + integration (fakes; no OS side effects)
dart test -t version           # version/pubspec sync check
dart test --coverage=coverage  # collect coverage
```

Tests tagged `os-linux` / `os-macos` / `os-windows` drive a real init system and
are skipped by default; run them explicitly on a matching host (e.g.
`dart test -t os-macos`).

## Contributing

Issues and pull requests are welcome on
[GitHub](https://github.com/OmnyGrid/dart_service_manager).

# Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
